require "spec_helper"

RSpec.describe MsProjectImport::CreateWorkPackagesService do
  let(:user) { create(:admin) }
  let(:project) { create(:project, types: [task_type, milestone_type, summary_type]) }
  let(:task_type) { create(:type, name: "Task") }
  let(:milestone_type) { create(:type, name: "Milestone") }
  let(:summary_type) { create(:type, name: "Summary task") }

  before do
    create(:default_status)
    create(:default_priority)
  end

  def call(parsed)
    described_class.new(project:, user:, parsed:).call
  end

  it "creates work packages preserving the parent/child hierarchy" do
    parsed = {
      tasks: [
        { unique_id: 1, name: "Phase 1", start: "2026-01-05T08:00:00.0", finish: "2026-01-20T17:00:00.0",
          summary: true },
        { unique_id: 2, name: "Task A", start: "2026-01-05T08:00:00.0", finish: "2026-01-10T17:00:00.0",
          parent_task_unique_id: 1 },
        { unique_id: 3, name: "Task B", start: "2026-01-11T08:00:00.0", finish: "2026-01-20T17:00:00.0",
          parent_task_unique_id: 1 }
      ]
    }

    result = call(parsed)

    expect(result[:tasks_created]).to eq(3)
    phase = WorkPackage.find_by(subject: "Phase 1")
    task_a = WorkPackage.find_by(subject: "Task A")
    task_b = WorkPackage.find_by(subject: "Task B")

    expect(task_a.parent).to eq(phase)
    expect(task_b.parent).to eq(phase)
    expect(phase.type.name).to eq("Summary task")
    expect(task_a.type.name).to eq("Task")
    expect(task_a.duration).to be_present
    expect(task_a.duration).to be > 0
  end

  it "maps dates, marks milestones and sets schedule_manually so dates aren't recomputed" do
    parsed = {
      tasks: [
        { unique_id: 1, name: "Kickoff", start: "2026-03-02T08:00:00.0", finish: "2026-03-02T17:00:00.0",
          milestone: true, percent_complete: 100.0 }
      ]
    }

    call(parsed)
    wp = WorkPackage.find_by(subject: "Kickoff")

    expect(wp.type.name).to eq("Milestone")
    expect(wp.start_date).to eq(Date.new(2026, 3, 2))
    expect(wp.due_date).to eq(Date.new(2026, 3, 2))
    expect(wp.schedule_manually).to be true
  end

  it "sets done_ratio from percent_complete only when work_package_done_ratio setting is 'field'" do
    allow(Setting).to receive(:work_package_done_ratio).and_return("field")
    parsed = { tasks: [{ unique_id: 1, name: "T", start: "2026-01-05T08:00:00.0",
                         finish: "2026-01-06T17:00:00.0", percent_complete: 42.0 }] }

    call(parsed)

    expect(WorkPackage.find_by(subject: "T").done_ratio).to eq(42)
  end

  it "does not set done_ratio when work_package_done_ratio setting is 'status'" do
    allow(Setting).to receive(:work_package_done_ratio).and_return("status")
    parsed = { tasks: [{ unique_id: 1, name: "T", start: "2026-01-05T08:00:00.0",
                         finish: "2026-01-06T17:00:00.0", percent_complete: 42.0 }] }

    call(parsed)

    expect(WorkPackage.find_by(subject: "T").read_attribute(:done_ratio)).not_to eq(42)
  end

  it "creates relations with the FS/SS/FF/SF schedule_relation_type and lag converted to working days" do
    parsed = {
      tasks: [
        { unique_id: 1, name: "A", start: "2026-01-05T08:00:00.0", finish: "2026-01-06T17:00:00.0" },
        { unique_id: 2, name: "B", start: "2026-01-05T08:00:00.0", finish: "2026-01-06T17:00:00.0",
          predecessors: [{ predecessor_task_unique_id: 1, successor_task_unique_id: 2, type: "SS", lag: 28_800 }] }
      ]
    }

    result = call(parsed)
    expect(result[:relations_created]).to eq(1)

    relation = Relation.last
    expect(relation.from).to eq(WorkPackage.find_by(subject: "B"))
    expect(relation.to).to eq(WorkPackage.find_by(subject: "A"))
    expect(relation.relation_type).to eq(Relation::TYPE_FOLLOWS)
    expect(relation.schedule_relation_type).to eq("SS")
    expect(relation.lag).to eq(1)
  end

  it "falls back to FS for an unrecognized schedule relation type and skips relations with an unknown task id" do
    parsed = {
      tasks: [
        { unique_id: 1, name: "A", start: "2026-01-05T08:00:00.0", finish: "2026-01-06T17:00:00.0" },
        { unique_id: 2, name: "B", start: "2026-01-05T08:00:00.0", finish: "2026-01-06T17:00:00.0",
          predecessors: [{ predecessor_task_unique_id: 1, successor_task_unique_id: 2, type: "BOGUS" }] },
        { unique_id: 3, name: "C", start: "2026-01-05T08:00:00.0", finish: "2026-01-06T17:00:00.0",
          predecessors: [{ predecessor_task_unique_id: 999, successor_task_unique_id: 3, type: "FS" }] }
      ]
    }

    result = call(parsed)

    expect(result[:tasks_created]).to eq(3)
    expect(result[:relations_created]).to eq(1)
    expect(Relation.last.schedule_relation_type).to eq("FS")
  end

  it "skips a task with a blank name gracefully by using a placeholder subject" do
    parsed = { tasks: [{ unique_id: 1, name: "", start: "2026-01-05T08:00:00.0",
                         finish: "2026-01-06T17:00:00.0" }] }

    result = call(parsed)

    expect(result[:tasks_created]).to eq(1)
    expect(WorkPackage.last.subject).to eq("Untitled task")
  end
end
