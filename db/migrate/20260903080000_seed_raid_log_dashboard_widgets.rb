class SeedRaidLogDashboardWidgets < ActiveRecord::Migration[8.1]
  def up
    Project.find_each do |project|
      RaidLog::DashboardWidgetsService.call(project)
    end
  end

  def down
    RaidLog::DashboardWidgetsService::CHARTS.each do |chart|
      Query.where(name: chart[:title]).find_each do |query|
        Grids::Widget.where("options->>'queryId' = ?", query.id.to_s).destroy_all
        query.destroy
      end
    end
  end
end
