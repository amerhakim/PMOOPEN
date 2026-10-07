module VendorManagement
  module PurchaseOrders
    # Mirrors Vendors::TableComponent -- the same sortable-table +
    # checkbox + row-action pattern, applied to the PO summary list.
    class TableComponent < ::TableComponent
      columns :po_number, :issue_date, :vendor, :total_value, :total_paid, :remaining_in_po, :order_description,
              :delivery_status_qds, :delivery_status_customer, :payment_status
      sortable_columns :po_number, :issue_date, :total_value, :total_paid, :remaining_in_po, :order_description,
                        :delivery_status_qds, :delivery_status_customer

      options :can_edit, :project

      def initial_sort
        %i[po_number asc]
      end

      def headers
        columns.map { |column| [column.to_s, { caption: I18n.t("vendor_management.po_list_columns.#{column}") }] }
      end

      def empty_row_message
        I18n.t("vendor_management.purchase_orders.no_pos")
      end
    end
  end
end
