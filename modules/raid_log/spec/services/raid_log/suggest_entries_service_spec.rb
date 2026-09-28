require "spec_helper"

RSpec.describe RaidLog::SuggestEntriesService do
  before { RaidLog::TypesAndFieldsSeeder.call }

  let(:project) { create(:project, types: [Type.find_by!(name: "Risk")]) }
  let(:client) { instance_double(RaidLog::OllamaClient) }

  it "parses a well-formed JSON array response into normalized entries" do
    allow(client).to receive(:generate).and_return(
      [{ "subject" => "Vendor delay", "description" => "desc", "Probability" => "High", "Impact" => "Critical" }].to_json
    )

    result = described_class.new(project:, type_name: "Risk", count: 1, client:).call

    expect(result).to be_success
    expect(result.result.first[:subject]).to eq("Vendor delay")
  end

  it "recovers a JSON array embedded in extra prose" do
    allow(client).to receive(:generate).and_return(
      "Sure, here you go:\n" + [{ "subject" => "Delay" }].to_json + "\nHope that helps!"
    )

    result = described_class.new(project:, type_name: "Risk", count: 1, client:).call

    expect(result).to be_success
    expect(result.result.first[:subject]).to eq("Delay")
  end

  it "fails gracefully when the model returns nothing usable" do
    allow(client).to receive(:generate).and_return("not json at all")

    result = described_class.new(project:, type_name: "Risk", count: 1, client:).call

    expect(result).not_to be_success
  end

  it "fails gracefully when the local AI service is unreachable" do
    allow(client).to receive(:generate).and_raise(RaidLog::OllamaClient::Error, "connection refused")

    result = described_class.new(project:, type_name: "Risk", count: 1, client:).call

    expect(result).not_to be_success
    expect(result.message).to include("connection refused")
  end
end
