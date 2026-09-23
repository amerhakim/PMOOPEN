require_relative "../../spec_helper"

RSpec.describe VendorManagement::PoPayment do
  let(:project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:po) { VendorManagement::PurchaseOrder.create!(project:, vendor:) }

  it "requires a positive amount" do
    expect(described_class.new(purchase_order: po, amount: 0, paid_on: Date.today)).not_to be_valid
    expect(described_class.new(purchase_order: po, amount: -5, paid_on: Date.today)).not_to be_valid
    expect(described_class.new(purchase_order: po, amount: 10, paid_on: Date.today)).to be_valid
  end

  it "requires a paid_on date" do
    expect(described_class.new(purchase_order: po, amount: 10, paid_on: nil)).not_to be_valid
  end

  it "is destroyed along with its purchase order" do
    payment = po.po_payments.create!(amount: 50, paid_on: Date.today)
    po.destroy
    expect(described_class.exists?(payment.id)).to be false
  end

  it "saves and can update its description independently of note" do
    payment = po.po_payments.create!(amount: 50, paid_on: Date.today, description: "Down payment", note: "Wired same day")
    expect(payment.reload.description).to eq("Down payment")

    payment.update!(description: "Revised description")
    expect(payment.reload.description).to eq("Revised description")
    expect(payment.note).to eq("Wired same day")
  end
end

