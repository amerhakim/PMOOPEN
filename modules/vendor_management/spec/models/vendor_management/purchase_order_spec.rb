require_relative "../../spec_helper"

RSpec.describe VendorManagement::PurchaseOrder do
  let(:project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }

  it "auto-generates a po_number on create when none is given" do
    po = described_class.create!(project:, vendor:)
    expect(po.po_number).to match(/\APO-#{project.identifier.upcase}-\d{4}\z/)
  end

  it "keeps a manually-provided po_number instead of overwriting it" do
    po = described_class.create!(project:, vendor:, po_number: "QDS/CMSG-335/682")
    expect(po.po_number).to eq("QDS/CMSG-335/682")
  end

  it "enforces po_number uniqueness within a project" do
    described_class.create!(project:, vendor:, po_number: "PO-DUP-0001")
    dup = described_class.new(project:, vendor:, po_number: "PO-DUP-0001")
    expect(dup).not_to be_valid
  end

  it "rejects an unknown currency" do
    po = described_class.new(project:, vendor:, currency: "EUR")
    expect(po).not_to be_valid
  end

  it "requires a vendor" do
    po = described_class.new(project:, po_number: "PO-NO-VENDOR-0001")
    expect(po).not_to be_valid
    expect(po.errors[:vendor]).to be_present
  end

  it "recomputes total_value as line items are added, updated, and removed" do
    po = described_class.create!(project:, vendor:)
    line1 = po.po_line_items.create!(description: "Widget A", item_type: "hardware", quantity: 2, unit_price: 100)
    po.po_line_items.create!(description: "Widget B", item_type: "hardware", quantity: 1, unit_price: 50)
    expect(po.reload.total_value).to eq(250)

    line1.update!(quantity: 5)
    expect(po.reload.total_value).to eq(550)

    line1.destroy
    expect(po.reload.total_value).to eq(50)
  end

  describe "hand-entered total_value (no line items yet)" do
    it "keeps a directly-entered amount and recomputes remaining_in_po from it" do
      po = described_class.create!(project:, vendor:, total_value: 9999.50)
      expect(po.reload.total_value).to eq(9999.50)
      expect(po.remaining_in_po).to eq(9999.50)
      expect(po.payment_status).to eq("not_invoiced")
    end

    it "lets the first line item override a hand-entered amount" do
      po = described_class.create!(project:, vendor:, total_value: 9999.50)
      po.po_line_items.create!(description: "Widget", item_type: "hardware", quantity: 1, unit_price: 50)
      expect(po.reload.total_value).to eq(50)
      expect(po.remaining_in_po).to eq(50)
    end
  end

  describe "delivery status aggregation" do
    it "stays not_delivered with no line items" do
      po = described_class.create!(project:, vendor:)
      expect(po.delivery_status_qds).to eq("not_delivered")
    end

    it "moves to partially_delivered once some but not all lines are checked, and delivered once all are" do
      po = described_class.create!(project:, vendor:)
      line1 = po.po_line_items.create!(description: "A", item_type: "hardware", quantity: 1, unit_price: 10)
      line2 = po.po_line_items.create!(description: "B", item_type: "hardware", quantity: 1, unit_price: 10)

      expect(po.reload.delivery_status_qds).to eq("not_delivered")

      line1.update!(delivered_to_qds: true)
      expect(po.reload.delivery_status_qds).to eq("partially_delivered")

      line2.update!(delivered_to_qds: true)
      expect(po.reload.delivery_status_qds).to eq("delivered")
    end

    it "tracks Delivery to Customer independently of Delivery to QDS" do
      po = described_class.create!(project:, vendor:)
      line = po.po_line_items.create!(description: "A", item_type: "hardware", quantity: 1, unit_price: 10)
      line.update!(delivered_to_qds: true, delivered_to_customer: false)

      po.reload
      expect(po.delivery_status_qds).to eq("delivered")
      expect(po.delivery_status_customer).to eq("not_delivered")
    end
  end

  describe "payment totals and status" do
    it "starts not_invoiced with no payments" do
      po = described_class.create!(project:, vendor:)
      expect(po.payment_status).to eq("not_invoiced")
    end

    it "recomputes total_paid/remaining_in_po and payment_status as payments are added and removed" do
      po = described_class.create!(project:, vendor:)
      po.po_line_items.create!(description: "A", item_type: "hardware", quantity: 1, unit_price: 100)

      payment = po.po_payments.create!(amount: 40, paid_on: Date.today)
      po.reload
      expect(po.total_paid).to eq(40)
      expect(po.remaining_in_po).to eq(60)
      expect(po.payment_status).to eq("partially_paid")

      po.po_payments.create!(amount: 60, paid_on: Date.today)
      po.reload
      expect(po.remaining_in_po).to eq(0)
      expect(po.payment_status).to eq("paid")

      payment.destroy
      po.reload
      expect(po.total_paid).to eq(60)
      expect(po.payment_status).to eq("partially_paid")
    end
  end
end

