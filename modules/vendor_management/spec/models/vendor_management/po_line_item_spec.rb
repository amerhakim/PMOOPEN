require_relative "../../spec_helper"

RSpec.describe VendorManagement::PoLineItem do
  let(:project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:purchase_order) { VendorManagement::PurchaseOrder.create!(project:, vendor:) }

  it "computes line_total as quantity times unit_price" do
    line = purchase_order.po_line_items.create!(description: "Widget", item_type: "hardware", quantity: 3, unit_price: 25.5)
    expect(line.line_total).to eq(76.5)
  end

  it "requires a description" do
    line = purchase_order.po_line_items.new(item_type: "hardware", quantity: 1, unit_price: 1)
    expect(line).not_to be_valid
  end

  it "rejects an unknown item_type" do
    line = purchase_order.po_line_items.new(description: "x", item_type: "bogus", quantity: 1, unit_price: 1)
    expect(line).not_to be_valid
  end

  it "rejects zero or negative quantity" do
    line = purchase_order.po_line_items.new(description: "x", item_type: "hardware", quantity: 0, unit_price: 1)
    expect(line).not_to be_valid
  end
end
