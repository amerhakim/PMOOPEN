module VendorManagement
  module PurchaseOrdersOverview
    # Cross-project variant of VendorManagement::PurchaseOrders::TableComponent,
    # used only by the global Purchase Orders overview page. Lives in its
    # own namespace (not VendorManagement::PurchaseOrders) because
    # ::TableComponent#row_class resolves the row class as
    # "#{name.deconstantize}::RowComponent" -- sharing a namespace with
    # the real per-project TableComponent/RowComponent pair would have
    # silently picked up THEIR RowComponent instead of this one's.
    #
    # No checkboxes/bulk-delete and no row-action icons here (that stays
    # on the real per-project list) -- this table's only job is browse +
    # link into the real per-project workspace, not duplicate CRUD.
    class TableComponent < ::TableComponent
      columns :po_number, :project, :vendor, :issue_date, :total_value, :status,
              :delivery_status_qds, :delivery_status_customer, :payment_status
      sortable_columns :po_number, :issue_date, :total_value

      def initial_sort
        %i[po_number asc]
      end

      def headers
        columns.map { |column| [column.to_s, { caption: I18n.t("vendor_management.po_overview_columns.#{column}") }] }
      end

      def empty_row_message
        I18n.t("vendor_management.purchase_orders_overview.no_pos")
      end
    end
  end
end
