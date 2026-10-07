require "roo"
require_relative "../../spec_helper"

RSpec.describe "VendorManagement purchase order export/import round trip" do
  let(:project) { create(:project) }
  let!(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let!(:po) do
    VendorManagement::PurchaseOrder.create!(
      project:, vendor:, po_number: "PO-ACME-0001", currency: "QAR",
      issue_date: Date.new(2026, 1, 15), order_description: "Test order"
    )
  end

  def write_temp_xlsx(bytes)
    file = Tempfile.new(["purchase_orders", ".xlsx"])
    file.binmode
    file.write(bytes)
    file.close
    file
  end

  it "exports a real .xlsx with a header row and one row per purchase order" do
    bytes = VendorManagement::PurchaseOrderExport.new(project).call
    expect(bytes).to be_a(String)
    expect(bytes.bytesize).to be > 0

    file = write_temp_xlsx(bytes)
    sheet = Roo::Spreadsheet.open(file.path).sheet(0)
    expect(sheet.row(1)).to eq(VendorManagement::PurchaseOrderExport::COLUMNS)
    expect(sheet.row(2)[0..4]).to eq(["PO-ACME-0001", Date.new(2026, 1, 15), "Acme Supplies", 0, "QAR"])
  ensure
    file&.unlink
  end

  it "updates an existing PO (matched by PO Number within the project) instead of duplicating it" do
    bytes = VendorManagement::PurchaseOrderExport.new(project).call
    file = write_temp_xlsx(bytes)

    result = VendorManagement::PurchaseOrderImport.new(project, file.path).call

    expect(result.errors).to be_empty
    expect(result.updated).to eq(["PO-ACME-0001"])
    expect(result.created).to be_empty
    expect(VendorManagement::PurchaseOrder.where(project:).count).to eq(1)
  ensure
    file&.unlink
  end

  it "creates a new PO for a PO Number that doesn't already exist" do
    require "caxlsx"
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Purchase Orders") do |sheet|
      sheet.add_row(VendorManagement::PurchaseOrderExport::COLUMNS)
      sheet.add_row(["PO-NEW-0001", Date.today, "Acme Supplies", 500, "QAR", "New order"])
    end
    file = write_temp_xlsx(package.to_stream.read)

    result = VendorManagement::PurchaseOrderImport.new(project, file.path).call

    expect(result.created).to eq(["PO-NEW-0001"])
    new_po = VendorManagement::PurchaseOrder.find_by(project:, po_number: "PO-NEW-0001")
    expect(new_po.total_value).to eq(500)
  ensure
    file&.unlink
  end

  it "reports an error and skips a row whose vendor name doesn't exist yet" do
    require "caxlsx"
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Purchase Orders") do |sheet|
      sheet.add_row(VendorManagement::PurchaseOrderExport::COLUMNS)
      sheet.add_row(["PO-UNKNOWN-VENDOR-0001", Date.today, "Nonexistent Vendor Co", 100, "QAR", ""])
    end
    file = write_temp_xlsx(package.to_stream.read)

    result = VendorManagement::PurchaseOrderImport.new(project, file.path).call

    expect(result.created).to be_empty
    expect(result.errors.first).to include("not found")
  ensure
    file&.unlink
  end
end
