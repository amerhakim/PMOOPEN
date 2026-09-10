module RaidLog
  # Asks the local Ollama model to draft new RAID log entries for a project.
  # Never persists anything itself -- returns normalized suggestions for a
  # human to review, edit and confirm before they become real work packages
  # (see RaidLogAssistantController#create).
  class SuggestEntriesService
    MAX_CONTEXT_ENTRIES = 15

    def initialize(project:, type_name:, user_context: nil, count: 3, client: OllamaClient.new)
      @project = project
      @type = LogTypeFields.find_type!(type_name)
      @user_context = user_context.presence
      @count = count.to_i.clamp(1, 8)
      @client = client
    end

    def call
      raw_response = @client.generate(prompt, format: "json")
      entries = parse(raw_response)

      if entries.any?
        ServiceResult.success(result: entries)
      else
        ServiceResult.failure(message: I18n.t("raid_log.errors.no_suggestions"))
      end
    rescue OllamaClient::Error => e
      ServiceResult.failure(message: e.message)
    end

    private

    def prompt
      <<~PROMPT
        You are helping a project manager populate the #{@type.name} Log for the project "#{@project.name}".
        #{project_description_line}
        Existing #{@type.name} Log entries already recorded for this project (do not repeat these):
        #{existing_entries_text}

        Other recent work items in this project, for context on what is actually happening:
        #{recent_work_packages_text}
        #{user_context_line}
        Propose #{@count} new, realistic, mutually distinct #{@type.name} Log entries for this project.
        Respond with a JSON array of #{@count} object#{'s' if @count != 1}, even if #{@count == 1 ? 'it is' : 'there is'} only one -- never a single bare object.
        Each element must be a JSON object with these exact keys:
        - "subject": short title, required
        - "description": one to two sentence description
        #{field_lines}

        Example shape (values illustrative only): [{"subject": "...", "description": "...", ...}#{', {"subject": "...", ...}, ...' if @count > 1}]

        Respond with ONLY the JSON array. No markdown formatting, no commentary before or after it.
      PROMPT
    end

    def project_description_line
      text = @project.description.to_s
      return "" if text.blank?

      "Project description: #{text.truncate(800)}\n"
    end

    def user_context_line
      return "" unless @user_context

      "\nAdditional context from the user: #{@user_context}\n"
    end

    def field_lines
      LogTypeFields.field_spec_for(@type).map do |field|
        if field[:options]
          "- \"#{field[:name]}\": one of #{field[:options].map(&:inspect).join(', ')}"
        elsif field[:format] == "date"
          "- \"#{field[:name]}\": a date, formatted YYYY-MM-DD"
        else
          "- \"#{field[:name]}\": free text"
        end
      end.join("\n")
    end

    def existing_entries_text
      subjects = @project.work_packages.where(type: @type).order(created_at: :desc).limit(MAX_CONTEXT_ENTRIES).pluck(:subject)
      subjects.empty? ? "(none yet)" : subjects.map { |s| "- #{s}" }.join("\n")
    end

    def recent_work_packages_text
      subjects = @project.work_packages.where.not(type: @type).order(updated_at: :desc).limit(MAX_CONTEXT_ENTRIES).pluck(:subject)
      subjects.empty? ? "(none)" : subjects.map { |s| "- #{s}" }.join("\n")
    end

    def parse(raw_text)
      json = extract_json_array(raw_text)
      return [] unless json

      json.filter_map { |entry| LogTypeFields.normalize_entry(entry, @type) }
    end

    # The model is asked for a JSON array but (especially with a small local
    # model and count: 1) sometimes returns a single bare object instead --
    # tolerate that rather than discarding a perfectly usable suggestion.
    def extract_json_array(text)
      parsed = parse_json(text)
      case parsed
      when Array then parsed
      when Hash then [parsed]
      end
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError
      match = text[/[\[{].*[\]}]/m]
      return nil unless match

      begin
        JSON.parse(match)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
