require "spec_helper"

RSpec.describe PaymentTerms::Payment do
  shared_let(:project) { create(:project) }

  def contract_line(value)
    PaymentTerms::ContractLine.create!(project:, name: "Implementation", component_value: value)
  end

  it "computes value as percent of the contract line's value" do
    line = contract_line(500_000)
    payment = described_class.create!(contract_line: line, description: "20% on signing", percent: 20)

    expect(payment.value).to eq(100_000)
  end

  it "recomputes value when the contract line's own value changes" do
    line = contract_line(500_000)
    payment = described_class.create!(contract_line: line, description: "20% on signing", percent: 20)

    line.update!(component_value: 1_000_000)

    expect(payment.reload.value).to eq(200_000)
  end

  it "leaves value blank without a percent" do
    line = contract_line(500_000)
    payment = described_class.create!(contract_line: line, description: "TBD")

    expect(payment.value).to be_nil
  end

  it "computes percent from a directly-entered value when entered_field is \"value\"" do
    line = contract_line(500_000)
    payment = described_class.create!(contract_line: line, description: "Entered as an amount",
                                       value: 125_000, entered_field: "value")

    expect(payment.percent).to eq(25)
  end

  it "still derives value from percent when entered_field is \"percent\" (the default)" do
    line = contract_line(500_000)
    payment = described_class.create!(contract_line: line, description: "Entered as a percent",
                                       percent: 20, entered_field: "percent")

    expect(payment.value).to eq(100_000)
  end

  it "prefers the directly-entered value over a stale percent from a prior save" do
    line = contract_line(500_000)
    payment = described_class.create!(contract_line: line, description: "20% on signing", percent: 20)
    expect(payment.value).to eq(100_000)

    payment.update!(value: 250_000, entered_field: "value")

    expect(payment.reload.percent).to eq(50)
    expect(payment.value).to eq(250_000)
  end

  it "adopts the linked milestone's due date as the expected invoice date" do
    line = contract_line(100_000)
    milestone = create(:work_package, :is_milestone, project:, due_date: Date.new(2027, 3, 15))

    payment = described_class.create!(contract_line: line, description: "On milestone", milestone:)

    expect(payment.expected_invoice_date).to eq(Date.new(2027, 3, 15))
  end

  it "follows the milestone if its due date is rescheduled later" do
    line = contract_line(100_000)
    milestone = create(:work_package, :is_milestone, project:, due_date: Date.new(2027, 3, 15))
    payment = described_class.create!(contract_line: line, description: "On milestone", milestone:)

    call = WorkPackages::UpdateService.new(user: User.system, model: milestone).call(due_date: Date.new(2027, 4, 1))
    expect(call).to be_success

    expect(payment.reload.expected_invoice_date).to eq(Date.new(2027, 4, 1))
  end

  it "rejects a milestone that belongs to a different project" do
    line = contract_line(100_000)
    other_milestone = create(:work_package, :is_milestone)

    payment = described_class.new(contract_line: line, description: "Bad link", milestone: other_milestone)

    expect(payment).not_to be_valid
    expect(payment.errors[:milestone]).to be_present
  end
end
