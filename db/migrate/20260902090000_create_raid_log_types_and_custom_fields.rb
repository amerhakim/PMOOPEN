class CreateRaidLogTypesAndCustomFields < ActiveRecord::Migration[8.1]
  def up
    types = RaidLog::TypesAndFieldsSeeder.call
    backfill_existing_projects(types.values)
  end

  def down
    types = Type.where(name: RaidLog::TypesAndFieldsSeeder::TYPE_NAMES)
    WorkPackageCustomField.joins(:types).where(types: { id: types.select(:id) }).distinct.destroy_all
    types.destroy_all
    IssuePriority.where(name: "Critical").destroy_all
  end

  private

  def backfill_existing_projects(types)
    Project.find_each do |project|
      missing = types - project.types
      next if missing.empty?

      project.types += missing
    end
  end
end
