require_relative "../spec_helper"

RSpec.describe VendorManagementMailer do
  let(:user) { create(:user, firstname: "Test", lastname: "User", mail: "test@test.com") }
  let(:project) { create(:project, name: "TestProject") }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:purchase_order) do
    VendorManagement::PurchaseOrder.create!(project:, vendor:, po_number: "PO-TEST-0001", currency: "QAR")
  end

  describe "#po_needs_approval", with_settings: { host_name: "my.openproject.com" } do
    let(:mail) { described_class.po_needs_approval(user, purchase_order) }

    it "renders the subject" do
      expect(mail.subject).to eq("[TestProject] Purchase order PO-TEST-0001 needs your approval")
    end

    it "renders the receiver's mail" do
      expect(mail.to).to eq([user.mail])
    end

    it "renders the PO number and vendor into the body" do
      expect(mail.body.encoded).to match("PO-TEST-0001")
      expect(mail.body.encoded).to match("Acme Supplies")
    end

    it "renders the correct link to the PO in every format" do
      contents = mail.parts.map { |p| p.body.to_s }
      expect(contents).to all include("http://my.openproject.com/projects/#{project.identifier}/vendor_management/purchase_orders/#{purchase_order.id}/edit")
    end
  end

  describe "#po_decision_made", with_settings: { host_name: "my.openproject.com" } do
    context "when approved" do
      before { purchase_order.update_column(:status, "approved") }

      let(:mail) { described_class.po_decision_made(user, purchase_order) }

      it "renders the approved subject" do
        expect(mail.subject).to eq("[TestProject] Purchase order PO-TEST-0001 was approved")
      end
    end

    context "when rejected back to draft" do
      before { purchase_order.update_column(:status, "draft") }

      let(:mail) { described_class.po_decision_made(user, purchase_order) }

      it "renders the rejected subject" do
        expect(mail.subject).to eq("[TestProject] Purchase order PO-TEST-0001 was rejected")
      end
    end
  end
end
