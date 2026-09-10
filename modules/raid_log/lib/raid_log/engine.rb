module RaidLog
  class Engine < ::Rails::Engine
    include OpenProject::Plugins::ActsAsOpEngine

    register "raid_log",
             author_url: "https://www.openproject.org",
             bundled: true do
      project_module :raid_log do
        permission :use_raid_log_ai_assist,
                   { raid_log_assistant: %i[new propose create review_existing apply_review] },
                   permissible_on: :project
      end

      menu :project_menu,
           :raid_log_assistant,
           { controller: "/raid_log_assistant", action: "new" },
           if: ->(project) { project.module_enabled?(:raid_log) },
           after: :work_packages,
           caption: :label_raid_log_ai_assist,
           icon: "copilot"
    end

    config.to_prepare do
      WorkPackage.include(RaidLog::ScoreCalculation)
      Project.include(RaidLog::DashboardSeeding)

      # New projects don't otherwise pick up a bundled module automatically
      # -- add raid_log to the instance's default module set so freshly
      # created projects get it enabled without an admin having to do it by
      # hand. Existing projects are backfilled once, in
      # db/migrate/20260902093000_enable_raid_log_module_for_existing_projects.rb.
      #
      # Guarded: this to_prepare block also runs during asset precompilation
      # at image build time, which boots Rails against a stub "nulldb" with
      # no real database -- Setting.default_projects_modules returns nil
      # there rather than an empty array, and any DB write is best skipped
      # entirely rather than trusted to no-op safely.
      begin
        current = Array(Setting.default_projects_modules)
        Setting.default_projects_modules = current + ["raid_log"] unless current.include?("raid_log")
      rescue StandardError
        nil
      end
    end
  end
end
