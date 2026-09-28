require "spec_helper"

RSpec.describe RaidLog::ScoreCalculation do
  before_all do
    RaidLog::TypesAndFieldsSeeder.call
    create(:default_status)
    create(:default_priority)
  end

  shared_let(:project) { create(:project, types: [Type.find_by!(name: "Risk")]) }
  shared_let(:risk_type) { Type.find_by!(name: "Risk") }

  def risk_work_package(probability: nil, impact: nil)
    attributes = { project:, type: risk_type, subject: "Test risk" }
    attributes[:custom_field_values] = {}
    attributes[:custom_field_values][RaidLog::CustomFields.probability_field.id] =
      RaidLog::CustomFields.probability_field.custom_options.find_by!(value: probability).id if probability
    attributes[:custom_field_values][RaidLog::CustomFields.impact_field.id] =
      RaidLog::CustomFields.impact_field.custom_options.find_by!(value: impact).id if impact

    call = WorkPackages::CreateService.new(user: User.system).call(**attributes)
    expect(call).to be_success
    call.result
  end

  def score_of(work_package)
    work_package.reload.typed_custom_value_for(RaidLog::CustomFields.score_field)&.to_i
  end

  it "computes the score from probability and impact on create" do
    wp = risk_work_package(probability: "Medium", impact: "High")

    expect(score_of(wp)).to eq(6)
  end

  it "recomputes the score when probability or impact changes" do
    wp = risk_work_package(probability: "Low", impact: "Low")
    expect(score_of(wp)).to eq(1)

    call = WorkPackages::UpdateService.new(user: User.system, model: wp).call(
      custom_field_values: {
        RaidLog::CustomFields.impact_field.id => RaidLog::CustomFields.impact_field.custom_options.find_by!(value: "Critical").id
      }
    )
    expect(call).to be_success

    expect(score_of(call.result)).to eq(4)
  end

  it "leaves the score blank when probability or impact is missing" do
    wp = risk_work_package(probability: "High")

    expect(score_of(wp)).to be_nil
  end

  it "does not touch the score field for non-Risk types" do
    task_type = create(:type_task)
    task_project = create(:project, types: [task_type])
    call = WorkPackages::CreateService.new(user: User.system).call(
      project: task_project, type: task_type, subject: "Not a risk"
    )
    expect(call).to be_success
  end
end
