require "caxlsx"

module VendorManagement
  # Exports the current Vendor Master list to .xlsx. Column order matches
  # VendorImport's expected input order exactly, so "export, edit in
  # Excel, re-import" is a clean round-trip.
  class VendorExport
    COLUMNS = ["Name", "CR Number", "Category", "Country", "Contact Name", "Contact Email", "Contact Phone", "Status"].freeze

    def call
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Vendors") do |sheet|
        sheet.add_row(COLUMNS)

        VendorManagement::Vendor.includes(:vendor_categories).order(:name).each do |vendor|
          sheet.add_row([
            vendor.name,
            vendor.cr_number,
            vendor.category_list.join(", "),
            vendor.country,
            vendor.contact_name,
            vendor.contact_email,
            vendor.contact_phone,
            vendor.status
          ])
        end
      end

      package.to_stream.read
    end
  end
end
