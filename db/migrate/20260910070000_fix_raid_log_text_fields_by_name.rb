class FixRaidLogTextFieldsByName < ActiveRecord::Migration[8.1]
  # 20260909110000 and 20260909130000 converted Mitigation Action/Latest
  # Update/Notes/Root Cause/Resolution Action from long-text to
  # short-text format so they could appear as Query columns, but did it
  # via hardcoded custom_field ids (19, 20, 27, 31, 32) copied from the
  # dev database where those migrations were authored. Custom field ids
  # are auto-increment and NOT the same across databases -- on
  # production those ids pointed at different (or no) fields entirely,
  # so the real fields (4/5/13/17/18 there) were silently never
  # converted, leaving them as long-text and invisible in the Risks/
  # Issues list views despite ListViewsService correctly resolving them
  # by name. Same class of fields, done right this time: look up by
  # name so this works on any database, including a from-scratch deploy
  # with entirely different auto-increment ids.
  FIELD_NAMES = ["Mitigation Action", "Latest Update", "Notes", "Root Cause", "Resolution Action"].freeze

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
