require "roo"
require "caxlsx"

module VendorManagement
  # Bulk-adds line items to one PO from an .xlsx (Part No, Description,
  # Type, Qty, Unit Price, Section). Unlike VendorImport/PurchaseOrderImport
  # this always CREATES rather than matching-and-updating -- a line item
  # has no natural unique key to match on, so re-running an import simply
  # appends more lines (matching how someone would upload a fresh
  # quotation's line items onto an existing PO).
  class PoLineItemImport
    Result = Struct.new(:created, :errors, keyword_init: true)

    COLUMNS = ["Part No", "Description", "Type", "Qty", "Unit Price", "Section"].freeze

    # A ready-to-fill example file for the import screen's "Download
    # sample" link -- real column headers plus a couple of realistic rows
    # (grouped into a section, matching how the reference quotation this
    # module's PDF export was built from itself groups line items) so it
    # doubles as both a schema reference and something that imports
    # successfully as-is.
    def self.sample_xlsx
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Line Items") do |sheet|
        sheet.add_row(COLUMNS)
        sheet.add_row(["908-000462-003-000", "Luna Network HSM S790 Bundle", "hardware", 1, 72_890.00, ""])
        sheet.add_row(["976-000012-001-000", "Virtual CipherTrust Manager, k170v", "software_license", 2, 27_500.00,
                        "Optional: Thales CipherTrust Data Security Platform - Production"])
        sheet.add_row(["Hardware Shipping", "Hardware Shipping and Cargo Charges", "service", 1, 3_000.00,
                        "Shipping & Cargo Charges"])
      end
      package.to_stream.read
    end

    def initialize(purchase_order, file_path)
      @purchase_order = purchase_order
      @file_path = file_path
    end

    def call
      sheet = Roo::Spreadsheet.open(@file_path).sheet(0)
      created = []
      errors = []

      (2..sheet.last_row).each do |row_number|
        row = sheet.row(row_number)
        next if row.compact.empty?

        part_no, description, item_type, quantity, unit_price, section_label = row

        if description.blank?
          errors << "Row #{row_number}: missing Description, skipped."
          next
        end

        line = @purchase_order.po_line_items.new(
          part_no:,
          description:,
          item_type: VendorManagement::PoLineItem::ITEM_TYPES.include?(item_type.to_s) ? item_type : "other",
          quantity: quantity.presence || 1,
          unit_price: unit_price.presence || 0,
          section_label:
        )

        if line.save
          created << line.description
        else
          errors << "Row #{row_number} (#{description}): #{line.errors.full_messages.join(', ')}"
        end
      end

      Result.new(created:, errors:)
    end
  end
end
