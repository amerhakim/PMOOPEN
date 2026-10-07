require "roo"

module VendorManagement
  # Single-step import (see VendorImport for the same reasoning). Matches
  # an existing PO by PO Number within the given project and updates it;
  # otherwise creates a new one. Vendor is matched by name (case
  # insensitive) against this instance's Vendor Master list -- a row
  # naming a vendor that doesn't exist yet is reported as an error and
  # skipped, since a PO can't be saved without one.
  class PurchaseOrderImport
    Result = Struct.new(:created, :updated, :errors, keyword_init: true)

    def initialize(project, file_path)
      @project = project
      @file_path = file_path
    end

    def call
      sheet = Roo::Spreadsheet.open(@file_path).sheet(0)
      created = []
      updated = []
      errors = []

      # Row 1 is the header (see PurchaseOrderExport::COLUMNS) -- data starts row 2.
      (2..sheet.last_row).each do |row_number|
        row = sheet.row(row_number)
        next if row.compact.empty?

        po_number, po_date, vendor_name, amount, currency, order_description = row

        if po_number.blank?
          errors << "Row #{row_number}: missing PO Number, skipped."
          next
        end

        vendor = vendor_name.present? ? VendorManagement::Vendor.where("LOWER(name) = ?", vendor_name.to_s.strip.downcase).first : nil
        if vendor.nil?
          errors << "Row #{row_number} (#{po_number}): vendor \"#{vendor_name}\" not found, skipped."
          next
        end

        po = VendorManagement::PurchaseOrder.where(project: @project, po_number: po_number.to_s.strip).first ||
             VendorManagement::PurchaseOrder.new(project: @project, po_number: po_number.to_s.strip)
        was_new_record = po.new_record?

        po.vendor = vendor
        po.issue_date = parse_date(po_date)
        po.currency = currency.presence || "QAR"
        po.order_description = order_description
        po.total_value = amount if amount.present? && po.po_line_items.empty?

        if po.save
          was_new_record ? created << po.po_number : updated << po.po_number
        else
          errors << "Row #{row_number} (#{po_number}): #{po.errors.full_messages.join(', ')}"
        end
      end

      Result.new(created:, updated:, errors:)
    end

    private

    def parse_date(value)
      return nil if value.blank?
      return value if value.is_a?(Date)

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
