class ConvertIssueImpactToListField < ActiveRecord::Migration[8.1]
  # Needed for the PMO Dashboard's Risks & Issues severity chart to combine
  # Risk's "Impact" (already a Low/Medium/High/Critical list) with Issue's
  # own impact field -- which was free text and couldn't be tallied by
  # severity level. No real "Issue Impact" values existed yet on this
  # install (checked before writing this), so there's nothing to lose by
  # switching format outright.
  VALUES = ["Low", "Medium", "High", "Critical"].freeze

  def up
    field = WorkPackageCustomField.find_by(name: "Issue Impact")
    return unless field

    # field_format is attr_readonly on CustomField (by design -- switching
    # it is normally unsafe with existing data), so this goes through raw
    # SQL instead of the AR setter.
    field.custom_values.destroy_all
    execute("UPDATE custom_fields SET field_format = 'list' WHERE id = #{field.id}")

    field = WorkPackageCustomField.find(field.id)
    field.possible_values = VALUES
    field.save!
  end

  def down
    field = WorkPackageCustomField.find_by(name: "Issue Impact")
    return unless field

    field.custom_values.destroy_all
    execute("DELETE FROM custom_options WHERE custom_field_id = #{field.id}")
    execute("UPDATE custom_fields SET field_format = 'string' WHERE id = #{field.id}")
  end
end
