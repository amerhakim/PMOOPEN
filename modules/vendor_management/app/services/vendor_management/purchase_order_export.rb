require "caxlsx"

module VendorManagement
  # Exports one project's Purchase Orders master list to .xlsx. Column
  # order matches PurchaseOrderImport's expected input order so "export,
  # edit in Excel, re-import" is a clean round trip -- same convention as
  # VendorExport/VendorImport. Delivery/payment status columns are
  # included for information but are read-only (derived from line items
  # and payments respectively) -- ignored on import.
  class PurchaseOrderExport
    COLUMNS = ["PO Number", "PO Date", "Vendor", "Amount", "Currency", "Order Description",
               "Delivery QDS", "Delivery to Customer", "Payment Status", "Total Paid", "Remaining in PO"].freeze

    def initialize(project)
      @project = project
    end

    def call
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Purchase Orders") do |sheet|
        sheet.add_row(COLUMNS)

        VendorManagement::PurchaseOrder.where(project: @project).includes(:vendor).order(:po_number).each do |po|
          sheet.add_row([
            po.po_number,
            po.issue_date,
            po.vendor&.name,
            po.total_value,
            po.currency,
            po.order_description,
            po.delivery_status_qds,
            po.delivery_status_customer,
            po.payment_status,
            po.total_paid,
            po.remaining_in_po
          ])
        end
      end

      package.to_stream.read
    end
  end
end
