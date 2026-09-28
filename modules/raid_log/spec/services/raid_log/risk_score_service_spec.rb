require "spec_helper"

RSpec.describe RaidLog::RiskScoreService do
  it "multiplies the probability and impact weights" do
    expect(described_class.call(probability: "Low", impact: "Low")).to eq(1)
    expect(described_class.call(probability: "High", impact: "High")).to eq(9)
    expect(described_class.call(probability: "Medium", impact: "Critical")).to eq(8)
    expect(described_class.call(probability: "High", impact: "Critical")).to eq(12)
  end

  it "returns nil when either value is blank or unrecognized" do
    expect(described_class.call(probability: nil, impact: "High")).to be_nil
    expect(described_class.call(probability: "Low", impact: nil)).to be_nil
    expect(described_class.call(probability: "Unknown", impact: "High")).to be_nil
  end
end
