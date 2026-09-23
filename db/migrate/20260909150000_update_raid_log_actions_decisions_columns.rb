class UpdateRaidLogActionsDecisionsColumns < ActiveRecord::Migration[8.1]
  # Same pattern as 20260909140000 (Issues): go through
  # Query#column_names= + #save! so values land as Symbols, not the raw
  # update_column string-array bug fixed in 20260909120000.
  TITLES = %w[Actions Decisions].freeze

  def up
    TITLES.each do |title|
      view = RaidLog::ListViewsService::VIEWS.find { |v| v[:title] == title }
      columns = RaidLog::ListViewsService.resolve_columns(view[:columns])

      Query.where(name: title).find_each do |query|
        query.column_names = columns
        query.save!(validate: false)
      end
    end
  end

  def down
    old_columns = {
      "Actions" => %w[id subject status] + ["Action Category", "RAID Status", "Owner"],
      "Decisions" => %w[id subject status] + ["Decision Category", "Decision Status", "Owner"]
    }

    old_columns.each do |title, names|
      base = names.first(3)
      cf_names = names.drop(3)
      columns = base + cf_names.filter_map { |name|
        field = WorkPackageCustomField.find_by(name:)
        "cf_#{field.id}" if field
      }

      Query.where(name: title).find_each do |query|
        query.column_names = columns
        query.save!(validate: false)
      end
    end
  end
end
