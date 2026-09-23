module RaidLog
  class Engine < ::Rails::Engine
    include OpenProject::Plugins::ActsAsOpEngine

    # The 4 RAID types, each already backed by a starred work-packages-table
    # Query per project (see RaidLog::ListViewsService -- exact same
    # `name:` values as that service's VIEWS titles). Building a Proc URL
    # per project (rather than a static hash) is required here since the
    # target is a specific Query id, which differs project to project.
    RAID_TYPE_VIEWS = %w[Risks Issues Actions Decisions].freeze

    def self.raid_type_view_url(title)
      lambda do |project|
        query = project && Query.find_by(project:, name: title)
        if query
          { controller: "/work_packages", action: "index", project_id: project.id, query_id: query.id }
        else
          # Fallback if the seeded view is somehow missing for this
          # project (module re-enabled, seeding failed, etc.) -- send
          # them to the AI Assist wizard rather than a dead link.
          { controller: "/raid_log_assistant", action: "new" }
        end
      end
    end

    register "raid_log",
             author_url: "https://www.openproject.org",
             bundled: true do
      project_module :raid_log do
        permission :use_raid_log_ai_assist,
                   { raid_log_assistant: %i[new propose create review_existing apply_review] },
                   permissible_on: :project
      end

      # "RAID Log AI Assist" is now a parent with 5 children (same
      # parent+children pattern as Vendor Management's "Vendor and
      # Procurement" menu): the AI Assist wizard itself (mirrored as its
      # own child, same URL as the parent -- clicking either reaches it),
      # plus one quick-access child per RAID type linking straight to
      # that project's own Risks/Issues/Actions/Decisions work-packages
      # table view (the exact same saved views already reachable from
      # Work Packages' own "Starred views" section -- this just surfaces
      # them here too so Procurement/PM staff don't have to leave the
      # RAID Log AI Assist area to see them).
      menu :project_menu,
           :raid_log_assistant,
           { controller: "/raid_log_assistant", action: "new" },
           if: ->(project) { project.module_enabled?(:raid_log) },
           after: :work_packages,
           caption: :label_raid_log_ai_assist,
           icon: "copilot"

      menu :project_menu,
           :raid_log_assistant_new,
           { controller: "/raid_log_assistant", action: "new" },
           if: ->(project) { project.module_enabled?(:raid_log) },
           parent: :raid_log_assistant,
           caption: :label_raid_log_ai_assist_new

      RaidLog::Engine::RAID_TYPE_VIEWS.each do |title|
        menu :project_menu,
             :"raid_log_assistant_view_#{title.downcase}",
             RaidLog::Engine.raid_type_view_url(title),
             if: ->(project) { project.module_enabled?(:raid_log) },
             parent: :raid_log_assistant,
             caption: title
      end
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
