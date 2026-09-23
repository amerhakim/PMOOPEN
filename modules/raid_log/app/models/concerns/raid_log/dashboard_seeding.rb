module RaidLog
  # Seeds the 4 RAID log dashboard charts and the 4 RAID log list views
  # (Risks/Issues/Actions/Decisions) onto a brand new project right away,
  # so a PM sees them without having to add anything by hand. Existing
  # projects are backfilled once, in
  # db/migrate/20260903080000_seed_raid_log_dashboard_widgets.rb and
  # db/migrate/20260903090000_seed_raid_log_list_views.rb.
  module DashboardSeeding
    extend ActiveSupport::Concern

    included do
      after_create :raid_log_seed_dashboard_widgets
      after_create :raid_log_seed_list_views
    end

    private

    def raid_log_seed_dashboard_widgets
      RaidLog::DashboardWidgetsService.call(self)
    end

    def raid_log_seed_list_views
      RaidLog::ListViewsService.call(self)
    end
  end
end
