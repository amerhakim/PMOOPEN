require "spec_helper"

RSpec.describe RaidLog::LogTypeFields do
  before { RaidLog::TypesAndFieldsSeeder.call }

  let(:risk_type) { Type.find_by!(name: "Risk") }

  describe ".normalize_entry" do
    it "keeps a valid subject and matches list values case-insensitively" do
      raw = { "subject" => "Vendor delay", "description" => "Vendor slipping", "Probability" => "medium", "Impact" => "HIGH" }

      result = described_class.normalize_entry(raw, risk_type)

      expect(result[:subject]).to eq("Vendor delay")
      probability_field = RaidLog::CustomFields.probability_field
      impact_field = RaidLog::CustomFields.impact_field
      expect(result[:custom_field_values][probability_field.id]).to eq(
        probability_field.custom_options.find_by!(value: "Medium").id.to_s
      )
      expect(result[:custom_field_values][impact_field.id]).to eq(
        impact_field.custom_options.find_by!(value: "High").id.to_s
      )
    end

    it "drops list values that don't match any option" do
      raw = { "subject" => "Something", "Probability" => "Astronomically High" }

      result = described_class.normalize_entry(raw, risk_type)

      expect(result[:custom_field_values]).to be_empty
    end

    it "returns nil when there is no usable subject" do
      expect(described_class.normalize_entry({ "subject" => "" }, risk_type)).to be_nil
      expect(described_class.normalize_entry("not a hash", risk_type)).to be_nil
    end
  end
end
