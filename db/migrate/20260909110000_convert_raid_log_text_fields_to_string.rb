class ConvertRaidLogTextFieldsToString < ActiveRecord::Migration[8.1]
  # "Mitigation Action", "Latest Update", "Notes" on Risk were seeded as
  # field_format "text" (long/rich text) -- like the native "Description"
  # field, long-text custom fields can't be shown as work-package-table
  # columns at all (Queries::WorkPackages::Selects::CustomFieldSelect
  # filters them out), which silently dropped them from the "Risks" list
  # view. Converted to "string" (short text) so they're selectable;
  # existing values are all well under the 255-char string limit
  # (checked: max 76 chars across all three), so nothing is truncated.
  # field_format is attr_readonly on CustomField -- same as the earlier
  # "Issue Impact" list-format migration, has to go through raw SQL
  # rather than the normal AR setter.
  #
  # Looked up by NAME, not id -- custom_field ids are per-database
  # auto-increment, so hardcoding them (as this migration originally
  # did) works on whichever database it was authored against and
  # silently no-ops (or worse, touches unrelated fields) on any other.
  FIELD_NAMES = ["Mitigation Action", "Latest Update", "Notes"].freeze

  def up
    ids = WorkPackageCustomField.where(name: FIELD_NAMES).pluck(:id)
    return if ids.empty?

    execute("UPDATE custom_fields SET field_format = 'string' WHERE id IN (#{ids.join(',')})")
  end

  def down
    ids = WorkPackageCustomField.where(name: FIELD_NAMES).pluck(:id)
    return if ids.empty?

    execute("UPDATE custom_fields SET field_format = 'text' WHERE id IN (#{ids.join(',')})")
  end
end
