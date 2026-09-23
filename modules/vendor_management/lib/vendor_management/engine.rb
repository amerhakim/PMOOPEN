module VendorManagement
  class Engine < ::Rails::Engine
    include OpenProject::Plugins::ActsAsOpEngine

    register "vendor_management",
             author_url: "https://www.openproject.org",
             bundled: true do
      # Vendor Master (Phase 1) is company-wide data, not scoped to any
      # one project -- REQ-VEN-02 explicitly says a vendor can be linked
      # to POs across many different projects -- so it stays reachable
      # only via the global menu entry below, with its own role-based
      # check in VendorManagementController. Purchase Orders (this
      # phase), by contrast, really are one-per-project (REQ-PO-01), so
      # THEY get the normal per-project module/permission treatment, same
      # shape as every other custom module in this fork.
      project_module :vendor_management do
        permission :view_vendor_management,
                   { purchase_orders: %i[index edit export_pdf export_excel download_quotation_file] },
                   permissible_on: :project
        permission :edit_vendor_management,
                   { purchase_orders: %i[
                     new create update destroy bulk_destroy
                     import_new import_create
                     new_line_item create_line_item edit_line_item update_line_item destroy_line_item
                     import_line_items_new import_line_items_sample import_line_items_create
                     update_delivery_status mark_all_delivered
                     create_payment edit_payment update_payment destroy_payment destroy_quotation_file
                     submit_for_approval
                   ] },
                   permissible_on: :project
        # Separate from edit_vendor_management on purpose -- submitting a
        # PO for approval (above) is a Procurement action, but actually
        # signing off on a step is meant for whoever the BRD's approval
        # chain names (Director/DGM/GM-level titles that don't map onto
        # any OpenProject role that exists yet). The chain itself is a
        # global, company-wide config, not tied to any one project.
        permission :manage_vendor_management_approvals,
                   { purchase_orders: %i[approve_step reject_step] },
                   permissible_on: :project
      end

      # Company-wide "Vendor and Procurement" entry, right under Home --
      # a parent with two children (same nested pattern core itself uses
      # for e.g. "Users and permissions" in config/initializers/menus.rb):
      # the existing global Vendors list, and the new cross-project
      # Purchase Orders overview. The parent's own URL intentionally
      # matches its first child's (Vendors) -- same duplication core's
      # own admin menu uses, clicking the parent label itself just goes
      # to the most natural default landing page.
      menu :global_menu,
           :vendor_management,
           { controller: "/vendor_management", action: "index" },
           caption: :label_vendor_management_home,
           icon: "package",
           after: :pmo_dashboard,
           if: ->(_) { User.current.logged? }

      menu :global_menu,
           :vendor_management_vendors_home,
           { controller: "/vendor_management", action: "index" },
           caption: :label_vendor_management,
           parent: :vendor_management,
           if: ->(_) { User.current.logged? }

      menu :global_menu,
           :vendor_management_purchase_orders_home,
           { controller: "/purchase_orders_overview", action: "index" },
           caption: :label_vendor_management_purchase_orders,
           parent: :vendor_management,
           if: ->(_) { User.current.logged? }

      menu :project_menu,
           :vendor_management_purchase_orders,
           { controller: "/purchase_orders", action: "index" },
           if: ->(project) { project.module_enabled?(:vendor_management) },
           after: :payment_terms,
           caption: :label_vendor_management_purchase_orders,
           icon: "package"
    end

    # Reassigns POs to a project once its "O&D" custom field value
    # matches -- see Patches::CustomValuePatch for the actual logic.
    patches %w[CustomValue]

    config.to_prepare do
      # New projects don't otherwise pick up a bundled module automatically
      # -- same guard payment_terms/raid_log use: this block also runs
      # during asset precompilation at image build time, which boots
      # Rails against a stub "nulldb" with no real database.
      begin
        current = Array(Setting.default_projects_modules)
        Setting.default_projects_modules = current + ["vendor_management"] unless current.include?("vendor_management")
      rescue StandardError
        nil
      end
    end
  end
end


