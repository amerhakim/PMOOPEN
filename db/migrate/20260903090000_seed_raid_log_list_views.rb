class SeedRaidLogListViews < ActiveRecord::Migration[8.1]
  def up
    Project.find_each do |project|
      RaidLog::ListViewsService.call(project)
    end
  end

  def down
    titles = RaidLog::ListViewsService::VIEWS.map { |view| view[:title] }
    Query.where(name: titles).destroy_all
  end
end
