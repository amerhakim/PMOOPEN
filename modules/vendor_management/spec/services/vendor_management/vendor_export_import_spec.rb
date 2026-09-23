require "roo"
require_relative "../../spec_helper"

RSpec.describe "VendorManagement vendor export/import round trip" do
  let!(:vendor) do
    VendorManagement::Vendor.create!(
      name: "Acme Supplies",
      status: "active",
      country: "Qatar",
      contact_name: "Sara",
      contact_email: "sara@acme.test",
      contact_phone: "555-1234",
      category_list: %w[Hardware Software]
    )
  end

  def write_temp_xlsx(bytes)
    file = Tempfile.new(["vendors", ".xlsx"])
    file.binmode
    file.write(bytes)
    file.close
    file
  end

  it "exports a real .xlsx with a header row and one row per vendor" do
    bytes = VendorManagement::VendorExport.new.call
    expect(bytes).to be_a(String)
    expect(bytes.bytesize).to be > 0

    file = write_temp_xlsx(bytes)
    sheet = Roo::Spreadsheet.open(file.path).sheet(0)
    expect(sheet.row(1)).to eq(VendorManagement::VendorExport::COLUMNS)
    expect(sheet.row(2)).to eq(
      ["Acme Supplies", nil, "Hardware, Software", "Qatar", "Sara", "sara@acme.test", "555-1234", "active"]
    )
  ensure
    file&.unlink
  end

  it "updates an existing vendor (matched by name) instead of duplicating it" do
    bytes = VendorManagement::VendorExport.new.call
    file = write_temp_xlsx(bytes)

    result = VendorManagement::VendorImport.new(file.path).call

    expect(result.errors).to be_empty
    expect(result.updated).to eq(["Acme Supplies"])
    expect(result.created).to be_empty
    expect(VendorManagement::Vendor.count).to eq(1)
  ensure
    file&.unlink
  end

  it "creates a new vendor for a name that doesn't already exist" do
    require "caxlsx"
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Vendors") do |sheet|
      sheet.add_row(VendorManagement::VendorExport::COLUMNS)
      sheet.add_row(["Brand New Vendor", "CR-1", "Service", "Oman", "", "", "", "active"])
    end
    file = Tempfile.new(["vendors", ".xlsx"])
    file.binmode
    file.write(package.to_stream.read)
    file.close

    result = VendorManagement::VendorImport.new(file.path).call

    expect(result.errors).to be_empty
    expect(result.created).to eq(["Brand New Vendor"])
    created = VendorManagement::Vendor.find_by(name: "Brand New Vendor")
    expect(created.category_list).to eq(["Service"])
  ensure
    file&.unlink
  end
end
