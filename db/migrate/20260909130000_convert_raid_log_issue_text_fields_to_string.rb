class ConvertRaidLogIssueTextFieldsToString < ActiveRecord::Migration[8.1]
  # "Root Cause" and "Resolution Action" were seeded as field_format
  # "text" (long/rich text) -- like Description, long-text custom fields
  # can't be shown as work-package-table columns at all (see the
  # identical fix for Risk's Mitigation Action/Latest Update/Notes in
  # 20260909110000). No existing values on the database this was
  # authored against, so no truncation risk there -- but that's a
  # property of that specific database's data, not something this
  # migration can assume in general.
  #
  # Looked up by NAME, not id -- see 20260909110000's comment: custom
  # field ids are per-database auto-increment, so hardcoding them only
  # works on the database the migration was authored against.
  FIELD_NAMES = ["Root Cause", "Resolution Action"].freeze

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
