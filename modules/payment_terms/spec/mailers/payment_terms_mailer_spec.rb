require "spec_helper"

RSpec.describe PaymentTermsMailer do
  let(:user) { create(:user, firstname: "Test", lastname: "User", mail: "test@test.com") }
  let(:project) { create(:project, name: "TestProject") }
  let(:line) { PaymentTerms::ContractLine.create!(project:, name: "Implementation", component_value: 1000) }
  let(:payment) do
    PaymentTerms::Payment.create!(
      contract_line: line,
      description: "First installment",
      percent: 50,
      invoiced: false,
      expected_invoice_date: Date.current - 5
    )
  end

  describe "#invoice_overdue", with_settings: { host_name: "my.openproject.com" } do
    let(:mail) { described_class.invoice_overdue(user, payment) }

    it "renders the subject" do
      expect(mail.subject).to eq("[TestProject] Invoice overdue: First installment")
    end

    it "renders the receiver's mail" do
      expect(mail.to).to eq([user.mail])
    end

    it "renders the payment description into the body" do
      expect(mail.body.encoded).to match("First installment")
    end

    it "renders the correct link to the payment in every format" do
      contents = mail.parts.map { |p| p.body.to_s }
      expect(contents).to all include("http://my.openproject.com/projects/#{project.identifier}/payment_terms/payments/#{payment.id}/edit")
    end
  end
end
