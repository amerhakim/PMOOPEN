require "spec_helper"

RSpec.describe Notifications::MailService::PaymentTerms::PaymentStrategy do
  let(:project) { create(:project) }
  let(:user) { create(:user) }
  let(:line) { PaymentTerms::ContractLine.create!(project:, name: "Payments", component_value: 1000) }
  let(:payment) { PaymentTerms::Payment.create!(contract_line: line, description: "P", value: 10, entered_field: "value") }
  let(:notification) { instance_double(Notification, resource: payment, recipient: user) }
  let(:delivery) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }

  it "sends the overdue email while the project is active" do
    allow(PaymentTermsMailer).to receive(:invoice_overdue).and_return(delivery)

    described_class.send_mail(notification)

    expect(PaymentTermsMailer).to have_received(:invoice_overdue).with(user, payment)
  end

  it "sends the archived email once the project is archived" do
    project.update_columns(active: false)
    allow(PaymentTermsMailer).to receive(:project_archived).and_return(delivery)

    described_class.send_mail(notification)

    expect(PaymentTermsMailer).to have_received(:project_archived).with(user, payment)
  end
end
