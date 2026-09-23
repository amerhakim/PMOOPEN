class RemoveRaidLogTrackField < ActiveRecord::Migration[8.1]
  # Requested by the user for Risk/Issue/Action/Decision: the "Track"
  # field (CM-AWS/CM-Fortinet/.../Cross-Track) is no longer wanted.
  # RaidLog::TypesAndFieldsSeeder no longer creates it for fresh installs;
  # this drops it (and any values already entered against it) for
  # existing ones.
  TRACK_VALUES = [
    "CM-AWS", "CM-Fortinet", "CM-Datadog", "QDS-ESM", "QDS-ECM",
    "UD-WSO2", "UD-UnifyApps", "UD-Data-Migration", "Najm", "Cross-Track"
  ].freeze

  def up
    WorkPackageCustomField.find_by(name: "Track")&.destroy
  end

  def down
    types = Type.where(name: %w[Risk Issue Action Decision]).to_a
    return if types.empty?

    field = WorkPackageCustomField.find_or_create_by!(name: "Track") do |cf|
      cf.field_format = "list"
      cf.is_for_all = true
      cf.is_filter = true
      cf.editable = true
      cf.searchable = false
    end
    field.possible_values = TRACK_VALUES
    field.types = types
    field.save!
  end
end
