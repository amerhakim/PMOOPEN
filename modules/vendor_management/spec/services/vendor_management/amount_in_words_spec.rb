require_relative "../../spec_helper"

RSpec.describe VendorManagement::AmountInWords do
  def words(amount, currency)
    described_class.new(amount, currency).call
  end

  it "spells a whole QAR amount with no fraction" do
    expect(words(1, "QAR")).to eq("One Qatari Riyals Only")
  end

  it "spells a large whole SAR amount matching the reference document's own wording" do
    expect(words(360_345, "SAR")).to eq("Three Hundred Sixty Thousand Three Hundred Forty Five Saudi Riyals Only")
  end

  it "spells a fractional USD amount with the cents as NN/100" do
    expect(words(6051.50, "QAR")).to eq("Six Thousand Fifty One Qatari Riyals and 50/100 Only")
  end

  it "spells a whole-number USD amount using the mapped currency name" do
    expect(words(1_000_000, "USD")).to eq("One Million US Dollars Only")
  end

  it "spells an OMR amount below one whole unit" do
    expect(words(0.75, "OMR")).to eq("Zero Omani Rials and 75/100 Only")
  end
end
