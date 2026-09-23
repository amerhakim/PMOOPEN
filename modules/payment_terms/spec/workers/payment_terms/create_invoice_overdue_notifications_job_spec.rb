require "spec_helper"

RSpec.describe PaymentTerms::CreateInvoiceOverdueNotificationsJob do
  let(:finance_user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:project) do
    create(:project, member_with_permissions: {
             finance_user => %i[view_payment_terms edit_payment_terms],
             other_user => %i[view_payment_terms]
           })
  end
  let(:line) { PaymentTerms::ContractLine.create!(project:, name: "Implementation", component_value: 1000) }

  def create_payment(overdue:, invoiced: false)
    PaymentTerms::Payment.create!(
      contract_line: line,
      description: "Payment",
      percent: 50,
      invoiced:,
      expected_invoice_date: overdue ? Date.current - 5 : Date.current + 5
    )
  end

  it "notifies users with edit_payment_terms for an overdue, uninvoiced payment" do
    payment = create_payment(overdue: true)

    expect { described_class.perform_now }
      .to change { Notification.where(resource: payment).count }.from(0).to(1)

    notification = Notification.find_by(resource: payment)
    expect(notification.recipient).to eq(finance_user)
    expect(notification.reason).to eq("subscribed")
  end

  it "does not notify a user without edit_payment_terms" do
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
end
