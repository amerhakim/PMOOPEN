require "spec_helper"

RSpec.describe PaymentTerms::ArchiveSettledProjectsJob do
  let(:manager_role) { create(:project_role, name: "Project Manager", permissions: %i[view_payment_terms edit_payment_terms]) }
  let(:manager) { create(:user) }
  let(:project) { create(:project) }
  let(:line) { PaymentTerms::ContractLine.create!(project:, name: "Payments", component_value: 1000) }

  before do
    create(:member, project:, user: manager, roles: [manager_role])
    project.update_columns(status_code: Project.status_codes["finished"])
  end

  def pay(attrs = {})
    PaymentTerms::Payment.create!({ contract_line: line, description: "P", value: 100, entered_field: "value",
                                    invoiced: true, collected: true }.merge(attrs))
  end

  it "archives a finished project whose live payments are all collected, and notifies the manager" do
    pay
    pay(value: 200)

    expect { described_class.perform_now }.to change { Notification.where(recipient: manager).count }.by(1)
    expect(project.reload).not_to be_active
  end

  it "ignores cancelled payments when deciding" do
    pay
    pay(value: 300, cancelled: true, invoiced: false, collected: false)

    described_class.perform_now

    expect(project.reload).not_to be_active
  end

  it "keeps a project active while a payment is still uncollected" do
    pay
    pay(collected: false)

    described_class.perform_now

    expect(project.reload).to be_active
  end

  it "keeps a project active when a payment is not invoiced yet" do
    pay
    pay(invoiced: false, collected: false)

    described_class.perform_now

    expect(project.reload).to be_active
  end

  it "does not archive a project that is not finished" do
    pay
    project.update_columns(status_code: Project.status_codes["on_track"])

    described_class.perform_now

    expect(project.reload).to be_active
  end

  it "does not archive a finished project with no payments at all" do
    line

    described_class.perform_now

    expect(project.reload).to be_active
  end

  it "does not archive a project that only has cancelled payments" do
    pay(cancelled: true)

    described_class.perform_now

    expect(project.reload).to be_active
  end

  it "does not archive a project that still has an active subproject" do
    pay
    create(:project, parent: project)

    described_class.perform_now

    expect(project.reload).to be_active
  end

  it "does nothing the second time around" do
    pay
    described_class.perform_now

    expect { described_class.perform_now }.not_to change(Notification, :count)
  end
end
