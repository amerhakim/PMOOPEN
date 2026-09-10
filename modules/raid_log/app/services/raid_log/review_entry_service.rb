module RaidLog
  # Asks the local Ollama model to review one existing RAID log work package
  # and suggest corrections/completions. Never persists anything itself --
  # returns a normalized suggestion for a human to review and apply (see
  # RaidLogAiAssistsController#apply_review).
  class ReviewEntryService
    def initialize(work_package:, client: OllamaClient.new)
      @work_package = work_package
      @type = work_package.type
      unless LogTypeFields.type_names.include?(@type.name)
        raise ArgumentError, "#{@work_package.type.name} is not a RAID log type"
      end

      @client = client
    end

    def call
      raw_response = @client.generate(prompt, format: "json")
      suggestion = parse(raw_response)

      if suggestion
        ServiceResult.success(result: suggestion)
      else
        ServiceResult.failure(message: I18n.t("raid_log.errors.no_suggestions"))
      end
    rescue OllamaClient::Error => e
      ServiceResult.failure(message: e.message)
    end

    private

    def prompt
      <<~PROMPT
        You are reviewing one #{@type.name} Log entry from the project "#{@work_package.project.name}" for
        completeness, consistency and clarity. Suggest corrected or completed values -- do not invent an
        unrelated #{@type.name.downcase}, only refine the one given below.

        Current entry:
        #{current_entry_text}

        Return a single JSON object (not an array) with these possible keys -- include only the ones you are
        suggesting a change for, omit the rest: "subject", "description", #{field_names_quoted}.
        Respond with ONLY the JSON object. No markdown formatting, no commentary.
      PROMPT
    end

    def current_entry_text
      lines = [
        "\"subject\": #{@work_package.subject.inspect}",
        "\"description\": #{@work_package.description.to_s.inspect}"
      ]
      LogTypeFields.field_spec_for(@type).each do |field|
        cf = WorkPackageCustomField.find(field[:id])
        lines << "\"#{field[:name]}\": #{@work_package.formatted_custom_value_for(cf).to_s.inspect}"
      end
      lines.join("\n")
    end

    def field_names_quoted
      LogTypeFields.field_spec_for(@type).map { |f| "\"#{f[:name]}\"" }.join(", ")
    end

    def parse(raw_text)
      json = extract_json_object(raw_text)
      return nil unless json

      json["subject"] ||= @work_package.subject
      LogTypeFields.normalize_entry(json, @type)
    end

    def extract_json_object(text)
      JSON.parse(text)
    rescue JSON::ParserError
      match = text[/\{.*\}/m]
      return nil unless match

      begin
        JSON.parse(match)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
