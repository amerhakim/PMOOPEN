require_relative "../../../../spec_helper"

RSpec.describe Notifications::MailService::VendorManagement::PurchaseOrderStrategy do
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

  describe ".send_mail" do
    it "sends the needs-approval mail once a PO is submitted for approval" do
      User.current = submitter
      po = VendorManagement::PurchaseOrder.create!(project:, vendor:)
      po.submit_for_approval!
      journal = po.journals.reload.order(:version).last
      Notifications::CreateFromModelService.new(journal).call(true)
      notification = Notification.find_by(resource: po, recipient: approver)

      expect { described_class.send_mail(notification) }
        .to have_enqueued_mail(VendorManagementMailer, :po_needs_approval).with(approver, po)
    end

    it "sends the decision mail once the PO is approved" do
      User.current = submitter
      po = VendorManagement::PurchaseOrder.create!(project:, vendor:)
      po.submit_for_approval!
      Notifications::CreateFromModelService.new(po.journals.reload.order(:version).last).call(true)

      User.current = approver
      po.approve_step!(po.next_pending_step, approver.name)
      journal = po.journals.reload.order(:version).last
      Notifications::CreateFromModelService.new(journal).call(true)
      notification = Notification.find_by(resource: po, recipient: submitter, journal:)

      expect { described_class.send_mail(notification) }
        .to have_enqueued_mail(VendorManagementMailer, :po_decision_made).with(submitter, po)
    end
  end
end
