module PaymentTerms
  module Payments
    # One instance per Contract Line -- mirrors
    # VendorManagement::Vendors::TableComponent's approach (subclass core's
    # own ::TableComponent) but with sorting/pagination turned off, same as
    # core's own Statuses::TableComponent: several independent instances of
    # this component can appear on one page (one per contract line), and
    # core's sort_init/sort_update is a single global `sort` param that
    # cannot cleanly serve more than one sortable table at a time.
    class TableComponent < ::TableComponent
      columns :sn, :description, :percent, :value, :milestone,
              :invoiced, :expected_invoice_date, :collected,
              :invoice_number, :invoice_date, :comments

      options :can_edit
      options :contract_line

      def sortable?
        false
      end

      def headers
        columns.map { |column| [column.to_s, { caption: I18n.t("payment_terms.columns.#{header_key(column)}") }] }
      end

      def header_key(column)
        column == :description ? :payment : column
      end

      def empty_row_message
        I18n.t("payment_terms.index.no_payments")
      end
    end
  end
end
