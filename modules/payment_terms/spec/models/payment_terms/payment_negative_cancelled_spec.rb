require "spec_helper"

RSpec.describe PaymentTerms::Payment, "credits, cancelled payments and currency" do
  shared_let(:project) { create(:project) }
  let(:line) { PaymentTerms::ContractLine.create!(project:, name: "Payments", component_value: 1000, currency: "SAR") }

  def pay(attrs = {})
    described_class.create!({ contract_line: line, description: "P", entered_field: "value" }.merge(attrs))
  end

  it "accepts a negative value as a credit and derives a negative percent" do
    payment = pay(value: -100)

    expect(payment.value).to eq(-100)
    expect(payment.percent).to eq(-10)
  end

  it "still rejects a zero value" do
    expect { pay(value: 0) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects a discount larger than the whole line" do
    expect { pay(percent: -150, entered_field: "percent") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects a regular payment above 100% of the line" do
    expect { pay(percent: 120, entered_field: "percent") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "allows a cancelled payment above 100% of the line" do
    payment = pay(value: 1500, cancelled: true)

    expect(payment).to be_persisted
    expect(payment.percent).to eq(150)
  end

  it "keeps cancelled payments out of the live scope and out of percent_allocated" do
    pay(value: 600)
    pay(value: -100)
    pay(value: 400, cancelled: true)

    expect(described_class.live.count).to eq(2)
    expect(line.reload.percent_allocated).to eq(50)
  end

  it "keeps the exact entered value (no rounding drift) on a large line" do
    big = PaymentTerms::ContractLine.create!(project:, name: "Big", component_value: 14_173_513)
    payment = described_class.create!(contract_line: big, description: "odd amount", value: 191_267.37, entered_field: "value")

    expect(payment.reload.value).to eq(191_267.37)
  end

  it "stores a payment with no value as blank" do
    payment = described_class.create!(contract_line: line, description: "TBD", entered_field: "value")

    expect(payment.value).to be_nil
  end

  it "delegates currency to its contract line" do
    expect(pay(value: 10).currency).to eq("SAR")
  end
end

RSpec.describe PaymentTerms::ContractLine do
  shared_let(:project) { create(:project) }

  it "defaults to QAR" do
    expect(described_class.create!(project:, name: "L", component_value: 1).currency).to eq("QAR")
  end

  it "only accepts QAR and SAR" do
    line = described_class.new(project:, name: "L", component_value: 1, currency: "USD")

    expect(line).not_to be_valid
  end
end
