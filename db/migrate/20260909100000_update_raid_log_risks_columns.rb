class UpdateRaidLogRisksColumns < ActiveRecord::Migration[8.1]
  def up
    view = RaidLog::ListViewsService::VIEWS.find { |v| v[:title] == "Risks" }
    columns = RaidLog::ListViewsService.resolve_columns(view[:columns])

    Query.where(name: "Risks").find_each do |query|
      query.update_column(:column_names, columns)
    end
  end

  def down
    # Old default before this migration: id, subject, status, then the
    # Risk Type/Risk Status/Probability/Impact/Score/Owner custom fields.
    old_cf_names = ["Risk Type", "Risk Status", "Probability", "Impact", "Score", "Owner"]
    old_columns = %w[id subject status] + old_cf_names.filter_map { |name|
      field = WorkPackageCustomField.find_by(name:)
      "cf_#{field.id}" if field
    }

    Query.where(name: "Risks").find_each do |query|
      query.update_column(:column_names, old_columns)
    end
  end
end
