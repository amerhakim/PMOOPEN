module RaidLog
  # Shared helpers describing the four RAID log types and turning an AI's
  # raw (untrusted) JSON suggestions into safe custom_field_values for
  # WorkPackages::CreateService / UpdateService.
  module LogTypeFields
    module_function

    def type_names
      %w[Risk Issue Action Decision]
    end

    def find_type!(name)
      raise ArgumentError, "Unknown RAID log type: #{name.inspect}" unless type_names.include?(name)

      Type.find_by!(name:)
    end

    # [{ id:, name:, format:, options: [...] or nil }, ...] for the fields
    # attached to this type (Owner/Notes/etc are always included since
    # they're attached to every RAID type; type-specific fields come along
    # naturally because they're only attached to their own type).
    #
    # Non-editable fields (currently just Risk's Score) are deliberately
    # excluded -- those are computed deterministically elsewhere and must
    # never be something the AI is asked for or allowed to set.
    def field_spec_for(type)
      type.custom_fields.select(&:editable?).map do |cf|
        {
          id: cf.id,
          name: cf.name,
          format: cf.field_format,
          options: cf.field_format == "list" ? cf.possible_values.map(&:value) : nil
        }
      end
    end

    # raw: a Hash with string keys, as parsed from the AI's JSON response.
    # Returns nil if it isn't usable at all (no subject). Any key that
    # doesn't match a known field, or a list value that doesn't match one of
    # that field's options, is silently dropped -- the AI's output is
    # untrusted text, never assumed to already be valid.
    def normalize_entry(raw, type)
      return nil unless raw.is_a?(Hash)

      subject = raw["subject"].to_s.strip
      return nil if subject.blank?

      custom_field_values = field_spec_for(type).filter_map do |field|
        value = raw[field[:name]]
        next if value.blank?

        normalized = normalize_value(value, field)
        [field[:id], normalized] if normalized
      end.to_h

      {
        subject: subject.first(255),
        description: raw["description"].presence&.to_s,
        custom_field_values:
      }
    end

    def normalize_value(value, field)
      case field[:format]
      when "list"
        match = field[:options].find { |option| option.casecmp?(value.to_s.strip) }
        return nil unless match

        WorkPackageCustomField.find(field[:id]).custom_options.find_by(value: match)&.id&.to_s
      when "date"
        Date.parse(value.to_s).iso8601
      else
        value.to_s.first(4000)
      end
    rescue ArgumentError, TypeError
      nil
    end
  end
end
