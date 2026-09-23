require "roo"
require_relative "../../spec_helper"

RSpec.describe VendorManagement::PoLineItemImport do
  let(:project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:po) { VendorManagement::PurchaseOrder.create!(project:, vendor:) }

  def write_temp_xlsx(rows)
    require "caxlsx"
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Line Items") do |sheet|
      sheet.add_row(described_class::COLUMNS)
      rows.each { |row| sheet.add_row(row) }
    end
    file = Tempfile.new(["line_items", ".xlsx"])
    file.binmode
    file.write(package.to_stream.read)
    file.close
    file
  end

  it "creates a new line item per row, never matching/updating existing ones" do
    po.po_line_items.create!(description: "Existing item", item_type: "hardware", quantity: 1, unit_price: 10)
    file = write_temp_xlsx([["P-1", "Imported item", "hardware", 2, 50, "Section A"]])

    result = described_class.new(po, file.path).call

    expect(result.created).to eq(["Imported item"])
    expect(result.errors).to be_empty
    expect(po.po_line_items.count).to eq(2)

    imported = po.po_line_items.find_by(part_no: "P-1")
    expect(imported.quantity).to eq(2)
    expect(imported.unit_price).to eq(50)
    expect(imported.section_label).to eq("Section A")
  ensure
    file&.unlink
  end

  it "falls back to item_type 'other' for an unrecognized type instead of failing the row" do
    file = write_temp_xlsx([["P-2", "Weird type item", "not_a_real_type", 1, 5, ""]])

    result = described_class.new(po, file.path).call

    expect(result.errors).to be_empty
    expect(po.po_line_items.find_by(part_no: "P-2").item_type).to eq("other")
  ensure
    file&.unlink
  end

  it "reports an error and skips a row with no description" do
    file = write_temp_xlsx([["P-3", "", "hardware", 1, 5, ""]])

    result = described_class.new(po, file.path).call

    expect(result.created).to be_empty
    expect(result.errors.first).to include("missing Description")
  ensure
    file&.unlink
  end

  describe ".sample_xlsx" do
    it "generates a real .xlsx with the expected header row" do
      bytes = described_class.sample_xlsx
      expect(bytes).to be_a(String)
      expect(bytes.bytesize).to be > 0

      file = Tempfile.new(["sample", ".xlsx"])
      file.binmode
      file.write(bytes)
      file.close
      sheet = Roo::Spreadsheet.open(file.path).sheet(0)
      expect(sheet.row(1)).to eq(described_class::COLUMNS)
      expect(sheet.last_row).to be > 1
    ensure
      file&.unlink
    end

    it "imports cleanly as-is, every sample row valid" do
      file = Tempfile.new(["sample", ".xlsx"])
      file.binmode
      file.write(described_class.sample_xlsx)
      file.close

      result = described_class.new(po, file.path).call

      expect(result.errors).to be_empty
      expect(result.created.size).to be > 0
    ensure
      file&.unlink
    end
  end
end
