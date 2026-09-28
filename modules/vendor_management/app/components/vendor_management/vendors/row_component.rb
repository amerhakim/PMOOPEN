module VendorManagement
  module Vendors
    # Mirrors core's own Statuses::RowComponent -- one <tr>, one method per
    # column name, `button_links` for the trailing actions cell.
    class RowComponent < ::RowComponent
      def vendor
        model
      end

      def name
        link_to vendor.name, edit_vendor_management_vendor_path(vendor)
      end

      def category
        vendor.category_list.join(", ")
      end

      def country
        vendor.country
      end

      def contact_name
        vendor.contact_name
      end

      def contact_email
        vendor.contact_email
      end

      def contact_phone
        vendor.contact_phone
      end

      def status
        vendor.status.humanize
      end

      def button_links
        return [] unless table.can_edit

        [edit_link, delete_link]
      end

      def edit_link
        link_to(
          helpers.op_icon("icon icon-edit"),
          edit_vendor_management_vendor_path(vendor),
          title: I18n.t(:button_edit)
        )
      end

      def delete_link
        link_to(
          helpers.op_icon("icon icon-delete"),
          vendor_management_vendor_path(vendor),
          data: { turbo_method: :delete, turbo_confirm: I18n.t(:text_are_you_sure) },
          title: I18n.t(:button_delete)
        )
      end
    end
  end
end
