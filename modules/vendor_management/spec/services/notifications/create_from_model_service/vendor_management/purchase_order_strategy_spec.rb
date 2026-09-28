require_relative "../../../../spec_helper"

RSpec.describe Notifications::CreateFromModelService::VendorManagement::PurchaseOrderStrategy do
  let(:submitter) { create(:user) }
  let(:approver) { create(:user) }
  let(:project) do
    create(:project, member_with_permissions: {
             submitter => %i[view_vendor_management edit_vendor_management],
             approver => %i[view_vendor_management manage_vendor_management_approvals]
           })
  end
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }

  let(:template) { VendorManagement::ApprovalChainTemplate.create!(project_id: nil, name: "Default Approval Chain") }

  before do
    template.approval_step_definitions.create!(sequence: 1, approver_title: "Logistics Coordinator")
  end

  describe ".subscribed_users" do
    it "returns nothing for a bare, never-submitted PO" do
      po = VendorManagement::PurchaseOrder.create!(project:, vendor:)
      journal = po.journals.reload.order(:version).last
      expect(described_class.subscribed_users(journal)).to be_empty
    end

    it "includes project members once submitted for approval" do
      User.current = submitter
      po = VendorManagement::PurchaseOrder.create!(project:, vendor:)
      po.submit_for_approval!

      journal = po.journals.reload.order(:version).last
      expect(described_class.subscribed_users(journal)).to include(approver)
    end

    it "returns the submitter once the PO is approved" do
      User.current = submitter
      po = VendorManagement::PurchaseOrder.create!(project:, vendor:)
      po.submit_for_approval!

      User.current = approver
      po.approve_step!(po.next_pending_step, approver.name)

      journal = po.journals.reload.order(:version).last
      expect(described_class.subscribed_users(journal)).to contain_exactly(submitter)
    end
  end

  describe ".permission" do
    it "requires manage_vendor_management_approvals while a decision is pending" do
      journal = instance_double(Journal, data: instance_double(Journal::VendorManagement::PurchaseOrderJournal, status: "pending_approval"))
      expect(described_class.permission(journal, :subscribed)).to eq(:manage_vendor_management_approvals)
    end

    it "only requires view_vendor_management once a decision has been made" do
      journal = instance_double(Journal, data: instance_double(Journal::VendorManagement::PurchaseOrderJournal, status: "approved"))
      expect(described_class.permission(journal, :subscribed)).to eq(:view_vendor_management)
    end
  end
end
