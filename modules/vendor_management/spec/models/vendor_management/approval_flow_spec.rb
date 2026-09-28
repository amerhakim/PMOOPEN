require_relative "../../spec_helper"

RSpec.describe "VendorManagement purchase order approval flow" do
  let(:project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:purchase_order) { VendorManagement::PurchaseOrder.create!(project:, vendor:) }

  let(:template) { VendorManagement::ApprovalChainTemplate.create!(project_id: nil, name: "Default Approval Chain") }

  before do
    template.approval_step_definitions.create!(sequence: 1, approver_title: "Logistics Coordinator")
    template.approval_step_definitions.create!(sequence: 2, approver_title: "Director-Operations & Logistics")
  end

  it "does nothing and returns false when no approval chain is configured" do
    VendorManagement::ApprovalChainTemplate.destroy_all
    expect(purchase_order.submit_for_approval!).to eq(false)
    expect(purchase_order.reload.status).to eq("draft")
  end

  it "snapshots the template's steps and moves the PO to pending_approval" do
    purchase_order.submit_for_approval!
    expect(purchase_order.reload.status).to eq("pending_approval")
    expect(purchase_order.po_approval_steps.pluck(:approver_title)).to eq(
      ["Logistics Coordinator", "Director-Operations & Logistics"]
    )
    expect(purchase_order.po_approval_steps.pluck(:status)).to eq(%w[pending pending])
  end

  it "records who submitted the PO for approval" do
    submitter = create(:user)
    User.current = submitter

    purchase_order.submit_for_approval!

    expect(purchase_order.reload.submitted_by).to eq(submitter)
  end

  it "tracks the status change in a real Journal snapshot" do
    purchase_order.submit_for_approval!

    # Not asserting on journals.count here -- a same-user, no-notes change
    # this soon after creation can legitimately get aggregated into the
    # existing journal rather than creating a new one (core behavior, see
    # Journals::CreateService#aggregatable_predecessor). What matters for
    # this phase is that the latest snapshot reflects the real change.
    snapshot = purchase_order.journals.reload.order(:version).last.data
    expect(snapshot).to be_a(Journal::VendorManagement::PurchaseOrderJournal)
    expect(snapshot.status).to eq("pending_approval")
  end

  it "only lets the lowest-sequence pending step be approved" do
    purchase_order.submit_for_approval!
    first_step, second_step = purchase_order.po_approval_steps.order(:sequence)

    expect(purchase_order.approve_step!(second_step, "Someone")).to eq(false)
    expect(purchase_order.approve_step!(first_step, "Ali")).to eq(true)
    expect(first_step.reload.status).to eq("approved")
    expect(first_step.approver_name).to eq("Ali")
  end

  it "moves the PO to approved once every step is approved" do
    purchase_order.submit_for_approval!
    first_step, second_step = purchase_order.po_approval_steps.order(:sequence)

    purchase_order.approve_step!(first_step, "Ali")
    expect(purchase_order.reload.status).to eq("pending_approval")

    purchase_order.approve_step!(second_step, "Sara")
    expect(purchase_order.reload.status).to eq("approved")
  end

  it "returns the PO to draft when a step is rejected" do
    purchase_order.submit_for_approval!
    first_step = purchase_order.po_approval_steps.order(:sequence).first

    purchase_order.reject_step!(first_step, "Ali")
    expect(first_step.reload.status).to eq("rejected")
    expect(purchase_order.reload.status).to eq("draft")
  end

  it "editing the template later does not change steps already snapshotted onto an in-flight PO" do
    purchase_order.submit_for_approval!
    template.approval_step_definitions.create!(sequence: 3, approver_title: "General Manager")

    expect(purchase_order.po_approval_steps.count).to eq(2)
  end
end
