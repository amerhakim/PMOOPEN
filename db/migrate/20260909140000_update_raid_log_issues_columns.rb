class UpdateRaidLogIssuesColumns < ActiveRecord::Migration[8.1]
  # Goes through Query#column_names= (converts to Symbol) + #save! rather
  # than update_column with a raw array -- see 20260909120000's comment
  # for the bug that caused (String/Symbol array-intersection mismatch in
  # Query#valid_column_subset!, silently emptying the column list on every
  # live page load despite looking correct via rails runner).
  def up
    view = RaidLog::ListViewsService::VIEWS.find { |v| v[:title] == "Issues" }
    columns = RaidLog::ListViewsService.resolve_columns(view[:columns])

    Query.where(name: "Issues").find_each do |query|
      query.column_names = columns
      query.save!(validate: false)
    end
  end

  def down
    old_cf_names = ["Issue Type", "RAID Status", "Owner"]
    old_columns = %w[id subject status] + old_cf_names.filter_map { |name|
      field = WorkPackageCustomField.find_by(name:)
      "cf_#{field.id}" if field
    }

    Query.where(name: "Issues").find_each do |query|
      query.column_names = old_columns
      query.save!(validate: false)
    end
  end
end
