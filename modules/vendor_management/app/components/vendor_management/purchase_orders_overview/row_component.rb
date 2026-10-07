module VendorManagement
  module PurchaseOrdersOverview
    class RowComponent < ::RowComponent
      def purchase_order
        model
      end

      def po_number
        link_to purchase_order.po_number,
                helpers.projects_edit_vendor_management_purchase_order_path(purchase_order.project, purchase_order)
      end

      def project
        project = purchase_order.project
        link = link_to(project.name, helpers.project_overview_path(project))
        return link if project.active?

        safe_join([link, " ", content_tag(:span, t("vendor_management.purchase_orders_overview.archived_label"),
                                          style: "background:#F6F8FA; color:#57606A; padding:1px 7px; border-radius:10px; " \
                                                 "font-size:11px; font-weight:600; white-space:nowrap;")])
      end

      def vendor
        purchase_order.vendor&.name
      end

      def issue_date
        purchase_order.issue_date&.strftime("%d-%b-%Y")
      end

      def total_value
        helpers.number_to_currency(purchase_order.total_value, unit: "#{purchase_order.currency} ", format: "%u%n")
      end

      def status
        purchase_order.status.humanize
      end

      def delivery_status_qds
        badge(purchase_order.delivery_status_qds)
      end

      def delivery_status_customer
        badge(purchase_order.delivery_status_customer)
      end

      def payment_status
        badge(purchase_order.payment_status)
      end

      def button_links
        []
      end

      private

      def badge(status)
        bg, fg = VendorManagement::PurchaseOrders::RowComponent::BADGE_COLORS.fetch(status, %w[#F6F8FA #57606A])
        content_tag(:span, status.humanize,
                    style: "background:#{bg}; color:#{fg}; padding:2px 8px; border-radius:10px; " \
                           "font-size:12px; font-weight:600; white-space:nowrap;")
      end
    end
  end
end
