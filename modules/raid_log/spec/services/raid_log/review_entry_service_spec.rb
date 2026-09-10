require "spec_helper"

RSpec.describe RaidLog::ReviewEntryService do
  before { RaidLog::TypesAndFieldsSeeder.call }

  let(:project) { create(:project, types: [Type.find_by!(name: "Risk")]) }
  let(:client) { instance_double(RaidLog::OllamaClient) }

  let(:work_package) do
    create(:default_status)
    create(:default_priority)
    WorkPackages::CreateService.new(user: User.system).call(
      project:, type: Type.find_by!(name: "Risk"), subject: "Original subject"
    ).result
  end

  it "raises for a non-RAID-log work package" do
    task_type = create(:type_task)
    task_project = create(:project, types: [task_type])
    create(:default_status)
    create(:default_priority)
    wp = WorkPackages::CreateService.new(user: User.system).call(
      project: task_project, type: task_type, subject: "Just a task"
    ).result

    expect { described_class.new(work_package: wp, client:) }.to raise_error(ArgumentError)
  end

  it "parses a suggested correction, defaulting the subject to the current one if omitted" do
    allow(client).to receive(:generate).and_return({ "description" => "Better description" }.to_json)

    result = described_class.new(work_package:, client:).call

    expect(result).to be_success
    expect(result.result[:subject]).to eq("Original subject")
    expect(result.result[:description]).to eq("Better description")
  end

  it "fails gracefully when the response has no usable JSON object" do
    allow(client).to receive(:generate).and_return("no json here")

    result = described_class.new(work_package:, client:).call

    expect(result).not_to be_success
  end
end
