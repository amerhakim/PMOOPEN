require "spec_helper"

RSpec.describe PaymentTerms::CreateInvoiceOverdueNotificationsJob do
  let(:project_manager_role) { create(:project_role, name: "Project Manager", permissions: %i[view_payment_terms edit_payment_terms]) }
  let(:program_manager_role) { create(:project_role, name: "Program Manager", permissions: %i[view_payment_terms edit_payment_terms]) }
  let(:project_manager) { create(:user) }
  let(:program_manager) { create(:user) }
  let(:other_user) { create(:user) }
  let(:project) { create(:project) }
  let(:line) { PaymentTerms::ContractLine.create!(project:, name: "Implementation", component_value: 1000) }

  before do
    create(:member, project:, user: project_manager, roles: [project_manager_role])
    create(:member, project:, user: program_manager, roles: [program_manager_role])
    create(:member, project:, user: other_user, roles: [create(:project_role, name: "Viewer", permissions: %i[view_payment_terms])])
  end

  def create_payment(overdue:, invoiced: false, due_today: false)
    date = if due_today
             Date.current
           else
             overdue ? Date.current - 5 : Date.current + 5
           end

    PaymentTerms::Payment.create!(
      contract_line: line,
      description: "Payment",
      percent: 50,
      invoiced:,
      expected_invoice_date: date
    )
  end

  it "notifies users holding Project Manager or Program Manager for an overdue, uninvoiced payment" do
    payment = create_payment(overdue: true)

    expect { described_class.perform_now }
      .to change { Notification.where(resource: payment).count }.from(0).to(2)

    recipients = Notification.where(resource: payment).map(&:recipient)
    expect(recipients).to contain_exactly(project_manager, program_manager)
  end

  it "notifies for a payment due today, not just strictly overdue ones" do
    payment = create_payment(overdue: true, due_today: true)

    expect { described_class.perform_now }
      .to change { Notification.where(resource: payment).count }.from(0).to(2)
  end

  it "does not notify a user who only has a Viewer role" do
    payment = create_payment(overdue: true)
    described_class.perform_now

    expect(Notification.where(resource: payment, recipient: other_user)).not_to exist
  end

  it "does not notify for a payment that is not yet due" do
    create_payment(overdue: false)

    expect { described_class.perform_now }.not_to change(Notification, :count)
  end

  it "does not notify for a payment already marked invoiced" do
    create_payment(overdue: true, invoiced: true)

    expect { described_class.perform_now }.not_to change(Notification, :count)
  end

  it "does not create a duplicate notification on a second run" do
    payment = create_payment(overdue: true)
    described_class.perform_now

    expect { described_class.perform_now }.not_to change { Notification.where(resource: payment).count }
  end

  it "does not notify for a cancelled payment" do
    payment = create_payment(overdue: true)
    payment.update!(cancelled: true)

    expect { described_class.perform_now }.not_to change(Notification, :count)
  end

  it "does not notify for a project that is already archived" do
    create_payment(overdue: true)
    project.update_columns(active: false)

    expect { described_class.perform_now }.not_to change(Notification, :count)
  end
end
