module PaymentTerms
  class Engine < ::Rails::Engine
    include OpenProject::Plugins::ActsAsOpEngine

    register "payment_terms",
             author_url: "https://www.openproject.org",
             bundled: true do
      project_module :payment_terms do
        # Deliberately separate from view_work_packages/edit_work_packages:
        # payment terms carry contract value and must stay invisible to
        # anyone who only has generic work-package access (Functional
        # Manager, Technical Team Member) -- see
        # db/migrate/*_set_payment_terms_role_permissions.rb for exactly
        # who gets these.
        permission :view_payment_terms,
                   {
                     payment_terms: %i[index my_projects],
                     pmo_dashboard: %i[show my_projects],
                     "grids/widgets/pmo_dashboard": %i[show]
                   },
                   permissible_on: :project
        permission :edit_payment_terms,
                   { payment_terms: %i[
                     new_line create_line edit_line update_line destroy_line
                     new_payment create_payment edit_payment update_payment destroy_payment
                     bulk_destroy_payments
                   ] },
                   permissible_on: :project
      end

      menu :project_menu,
           :pmo_dashboard,
           { controller: "/pmo_dashboard", action: "show" },
           if: ->(project) { project.module_enabled?(:payment_terms) },
           after: :work_packages,
           caption: :label_pmo_dashboard,
           icon: "graph"

      menu :project_menu,
           :payment_terms,
           { controller: "/payment_terms", action: "index" },
           if: ->(project) { project.module_enabled?(:payment_terms) },
           after: :pmo_dashboard,
           caption: :label_payment_terms,
           icon: "credit-card"

      # Global sidebar entry (the one shown outside any project, right
      # under "Home") pointing at the cross-project carousel -- separate
      # from the per-project "PMO Dashboard" item above. `my_projects`
      # isn't project-scoped so there's no `view_payment_terms` project to
      # check here; it does its own per-row filtering (see
      # PmoDashboardController#my_projects), same as the sidebar's own
      # "My page"/"Portfolios" entries just gate on being logged in.
      menu :global_menu,
           :pmo_dashboard,
           { controller: "/pmo_dashboard", action: "my_projects" },
           caption: :label_pmo_dashboard,
           icon: "graph",
           after: :home,
           if: ->(_) { User.current.logged? || !Setting.login_required? }

      # Same idea as the PMO Dashboard entry above -- without this, the
      # consolidated invoices report was only reachable by typing its URL
      # from memory. Row-level visibility (own projects only, or every
      # project for PMO Director/admin) is enforced in
      # PaymentTermsController#my_projects itself, not by this menu item.
      menu :global_menu,
           :payment_terms,
           { controller: "/payment_terms", action: "my_projects" },
           caption: :label_payment_terms_report,
           icon: "credit-card",
           after: :pmo_dashboard,
           if: ->(_) { User.current.logged? || !Setting.login_required? }
    end

    config.to_prepare do
      WorkPackage.include(WorkPackages::PaymentMilestoneSync)
      WorkPackage.include(WorkPackages::DurationBasedEstimatedHours)

      # Makes "pmo_dashboard" a selectable identifier in the project
      # Overview/Dashboard grid's "+ Add widget" list -- the actual
      # authoritative registry consulted by the API schema
      # (GridSchemaRepresenter#assignable_widgets) is
      # Grids::Configuration's @widget_register, populated via
      # register_widget; the class-level `widgets "a", "b", ...` DSL in
      # Grids::Configuration::Registration subclasses is just one way to
      # feed it at boot, calling this same method directly works from any
      # engine without subclassing or editing modules/grids or
      # modules/overviews. Gated behind view_payment_terms so it can't even
      # be added to a dashboard by someone who couldn't see its content
      # anyway.
      Grids::Configuration.register_widget("pmo_dashboard", "Grids::Overview")
      Overviews::GridRegistration.widget_strategy("pmo_dashboard") do
        allowed ->(user, project) { user.allowed_in_project?(:view_payment_terms, project) }
      end

      # New projects don't otherwise pick up a bundled module automatically
      # -- see the identical guard in RaidLog::Engine for why this needs a
      # rescue: this block also runs during asset precompilation at image
      # build time, which boots Rails against a stub "nulldb" with no real
      # database, where Setting.default_projects_modules returns nil
      # rather than an empty array.
      begin
        current = Array(Setting.default_projects_modules)
        Setting.default_projects_modules = current + ["payment_terms"] unless current.include?("payment_terms")
      rescue StandardError
        nil
      end
    end

    # Daily check for payments past their expected_invoice_date that
    # haven't been marked invoiced yet -- registered from here (not
    # config/initializers/cronjobs.rb, a core file) since
    # Rails.application.config.good_job.cron is a plain accumulating Rails
    # config any initializer can merge into, matching the SAME
    # after_initialize timing core's own cronjobs.rb uses. See
    # openproject_notification_system memory for the full design.
    config.after_initialize do
      Rails.application.config.good_job.cron.merge!(
        "PaymentTerms::CreateInvoiceOverdueNotificationsJob": {
          cron: "0 6 * * *",
          class: "PaymentTerms::CreateInvoiceOverdueNotificationsJob"
        }
      )
    end
  end
end
