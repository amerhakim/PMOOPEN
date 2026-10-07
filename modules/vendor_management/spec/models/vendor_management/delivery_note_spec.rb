require_relative "../../spec_helper"

RSpec.describe VendorManagement::DeliveryNote do
  let(:project) { create(:project) }
  let(:other_project) { create(:project) }
  let(:user) { create(:admin) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:purchase_order) { VendorManagement::PurchaseOrder.create!(project:, vendor:) }
  let(:pdf) { "%PDF-1.4\n%%EOF\n" }

  def note(**attrs)
    described_class.new({ project:, uploaded_by: user, filename: "dn.pdf", content_type: "application/pdf", byte_size: pdf.bytesize, data: pdf }.merge(attrs))
  end

  it "accepts a PDF linked to a purchase order of the same project" do
    expect(note(purchase_order:)).to be_valid
  end

  it "accepts a project file that is not linked to any purchase order" do
    expect(note).to be_valid
  end

  it "rejects a purchase order from another project" do
    expect(note(project: other_project, purchase_order:)).not_to be_valid
  end

  it "rejects extensions that are not PDF or images" do
    expect(note(filename: "run.exe")).not_to be_valid
  end

  it "rejects a file whose content does not match its extension" do
    result = note(filename: "fake.pdf", data: "MZ not a pdf")
    expect(result).not_to be_valid
    expect(result.errors.full_messages.join).to match(/does not look like a PDF/)
  end

  it "accepts a PNG photo" do
    png = "\x89PNG\r\n\x1a\n".b + ("0" * 20)
    expect(note(filename: "photo.png", content_type: "image/png", data: png, byte_size: png.bytesize)).to be_valid
  end

  it "keeps the file when its purchase order is deleted" do
    saved = note(purchase_order:)
    saved.save!
    purchase_order.destroy
    expect(saved.reload.purchase_order_id).to be_nil
  end

  it "lists notes without loading the file bytes" do
    note.save!
    row = described_class.without_data.first
    expect(row.attributes.keys).not_to include("data")
  end
end

RSpec.describe VendorManagement::PurchaseOrder, "#approval_in_use?" do
  let(:project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:purchase_order) { described_class.create!(project:, vendor:) }

  it "is false when no approval chain has steps and the PO has none" do
    expect(purchase_order.approval_in_use?).to be(false)
  end

  it "is true once the approval chain has a step" do
    VendorManagement::ApprovalChainTemplate.company_default.approval_step_definitions.create!(sequence: 1, approver_title: "Director")
    expect(purchase_order.approval_in_use?).to be(true)
  end
end
