module Impersonation
  class Engine < ::Rails::Engine
    include OpenProject::Plugins::ActsAsOpEngine

    register "impersonation",
             author_url: "https://www.openproject.org",
             bundled: true do
      # Dev/QA tool only, admin-only -- lets an admin instantly become any
      # other user to test role-specific behaviour (e.g. Vendor Management's
      # RBAC) without logging out and back in each time. No project_module
      # here: this is instance-wide, not something a project turns on/off.
      menu :global_menu,
           :impersonation,
           { controller: "/impersonations", action: "index" },
           caption: :label_impersonation,
           icon: "person",
           after: :vendor_management,
           if: ->(_) { User.current.admin? }
    end

    config.to_prepare do
      # Referencing the constant triggers Zeitwerk to load it, which is
      # what actually registers the hook listener (see
      # modules/avatars/lib/open_project/avatars/engine.rb for the same
      # pattern already used elsewhere in this codebase).
      Impersonation::Hooks
    end
  end
end
