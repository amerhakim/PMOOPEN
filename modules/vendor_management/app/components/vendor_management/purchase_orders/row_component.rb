module VendorManagement
  module PurchaseOrders
    # Mirrors Vendors::RowComponent -- one <tr>, one method per column,
    # button_links for the trailing actions cell.
    class RowComponent < ::RowComponent
      BADGE_COLORS = {
        "delivered" => %w[#DAFBE1 #1A7F37],
        "paid" => %w[#DAFBE1 #1A7F37],
        "partially_delivered" => %w[#FFF1E5 #9A6700],
        "partially_paid" => %w[#FFF1E5 #9A6700],
        "not_delivered" => %w[#F6F8FA #57606A],
        "not_invoiced" => %w[#F6F8FA #57606A]
      }.freeze

      def purchase_order
        model
      end

      def po_number
        link_to purchase_order.po_number, helpers.projects_edit_vendor_management_purchase_order_path(table.project, purchase_order)
      end

      def issue_date
        purchase_order.issue_date&.strftime("%d-%b-%Y")
      end

      def vendor
        purchase_order.vendor&.name
      end

      def total_value
        helpers.number_to_currency(purchase_order.total_value, unit: "#{purchase_order.currency} ", format: "%u%n")
      end

      def order_description
        purchase_order.order_description.to_s.truncate(60)
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

      def total_paid
        helpers.number_to_currency(purchase_order.total_paid, unit: "#{purchase_order.currency} ", format: "%u%n")
      end

      def remaining_in_po
        helpers.number_to_currency(purchase_order.remaining_in_po, unit: "#{purchase_order.currency} ", format: "%u%n")
      end

      def button_links
        return [] unless table.can_edit

        [edit_link, delete_link]
      end

      def edit_link
        link_to(
          helpers.op_icon("icon icon-edit"),
          helpers.projects_edit_vendor_management_purchase_order_path(table.project, purchase_order),
          title: I18n.t(:button_edit)
        )
      end

      def delete_link
        link_to(
          helpers.op_icon("icon icon-delete"),
          helpers.projects_vendor_management_purchase_order_destroy_path(table.project, purchase_order),
          data: { turbo_method: :delete, turbo_confirm: I18n.t(:text_are_you_sure) },
          title: I18n.t(:button_delete)
        )
      end

      private

      def badge(status)
        bg, fg = BADGE_COLORS.fetch(status, %w[#F6F8FA #57606A])
        content_tag(:span, status.humanize,
                    style: "background:#{bg}; color:#{fg}; padding:2px 8px; border-radius:10px; " \
                           "font-size:12px; font-weight:600; white-space:nowrap;")
      end
    end
  end
end
