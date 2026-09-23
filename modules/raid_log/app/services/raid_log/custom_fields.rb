module RaidLog
  # Looks up the RAID log's custom fields by the exact names created in
  # db/migrate/20260902090000_create_raid_log_types_and_custom_fields.rb.
  module CustomFields
    module_function

    def probability_field = WorkPackageCustomField.find_by(name: "Probability")

    def impact_field = WorkPackageCustomField.find_by(name: "Impact")

    def score_field = WorkPackageCustomField.find_by(name: "Score")
  end
end
