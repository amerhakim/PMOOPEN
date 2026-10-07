require "spec_helper"

RSpec.describe PaymentTerms::Payment, "collection dates" do
  shared_let(:project) { create(:project) }
  let(:line) { PaymentTerms::ContractLine.create!(project:, name: "Payments", component_value: 1000) }

  it "stores an expected and an actual collection date" do
    payment = described_class.create!(contract_line: line, description: "P", value: 100, entered_field: "value",
                                      invoiced: true, collected: true,
                                      expected_collection_date: Date.new(2026, 11, 1), actual_collection_date: Date.new(2026, 11, 9))

    expect(payment.reload.expected_collection_date).to eq(Date.new(2026, 11, 1))
    expect(payment.actual_collection_date).to eq(Date.new(2026, 11, 9))
  end

  it "keeps both dates optional" do
    payment = described_class.create!(contract_line: line, description: "P", value: 100, entered_field: "value")

    expect(payment.expected_collection_date).to be_nil
    expect(payment.actual_collection_date).to be_nil
  end
end
