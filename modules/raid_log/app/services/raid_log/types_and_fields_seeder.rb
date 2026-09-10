module RaidLog
  # Creates (idempotently) the 4 RAID log work package types and all their
  # custom fields. Used by db/migrate/20260902090000_create_raid_log_types_and_custom_fields.rb
  # and by specs that need real Type/CustomField rows -- the test database is
  # truncated between examples, so the migration having already run against
  # it is not enough; specs call RaidLog::TypesAndFieldsSeeder.call directly.
  class TypesAndFieldsSeeder
    RISK_TYPE_VALUES = [
      "Schedule", "Technical", "Resource", "Vendor/Subcontractor",
      "Compliance/Security", "Budget", "Stakeholder/Change", "Other"
    ].freeze

    RISK_STATUS_VALUES = ["New", "Open", "Closed", "Red", "Amber", "Green"].freeze
    PROBABILITY_VALUES = ["Low", "Medium", "High"].freeze
    IMPACT_VALUES = ["Low", "Medium", "High", "Critical"].freeze

    ISSUE_TYPE_VALUES = [
      "Blocker", "Escalation", "Change Request", "Constraint", "Budget / Cost",
      "Schedule", "Quality", "Scope", "Environment", "Broken Dependency"
    ].freeze

    RAID_STATUS_VALUES = ["Open", "Resolved", "On Hold", "Closed"].freeze

    ACTION_CATEGORY_VALUES = [
      "Technical Documentation", "Governance / Comms / Planning", "Licensing",
      "Resources", "Planning", "Escalation", "Mitigation", "Contingency", "Other"
    ].freeze

    DECISION_CATEGORY_VALUES = [
      "Architecture", "Commercial", "Scope", "Schedule", "Resource",
      "Technology", "Process", "Workspace ONE", "Other"
    ].freeze

    DECISION_STATUS_VALUES = ["Approved", "Pending", "Deferred", "Rejected", "Agreed", "On Hold"].freeze

    TYPE_NAMES = ["Risk", "Issue", "Action", "Decision"].freeze

    def self.call
      new.call
    end

    def call
      add_critical_priority

      risk = create_type("Risk", hexcode: "#D64545")
      issue = create_type("Issue", hexcode: "#E0A030")
      action = create_type("Action", hexcode: "#3B82C4")
      decision = create_type("Decision", hexcode: "#6B4FA0")

      # Shared across all four logs
      create_field("Owner", "string", types: [risk, issue, action, decision])
      create_field("Latest Update", "string", types: [risk, issue, action, decision])
      create_field("Notes", "string", types: [risk, issue, action, decision])
      create_field("Last Updated By", "string", types: [issue, action, decision])
      create_field("Date Resolved", "date", types: [issue, action])

      # Risk Log
      create_list_field("Risk Type", RISK_TYPE_VALUES, types: [risk])
      create_list_field("Risk Status", RISK_STATUS_VALUES, types: [risk])
      create_list_field("Probability", PROBABILITY_VALUES, types: [risk])
      create_list_field("Impact", IMPACT_VALUES, types: [risk])
      create_field("Mitigation Action", "string", types: [risk])
      # Deterministically computed from Probability x Impact -- see
      # RaidLog::RiskScoreService; not directly user-editable.
      create_field("Score", "int", types: [risk], editable: false)

      # Issue Log
      create_list_field("Issue Type", ISSUE_TYPE_VALUES, types: [issue])
      create_field("Issue Impact", "string", types: [issue])
      create_field("Root Cause", "string", types: [issue])
      create_field("Resolution Action", "string", types: [issue])

      # Action Log
      create_list_field("Action Category", ACTION_CATEGORY_VALUES, types: [action])

      # Shared between Issue and Action (identical value set in the source sheet)
      create_list_field("RAID Status", RAID_STATUS_VALUES, types: [issue, action])

      # Decision Log
      create_list_field("Decision Category", DECISION_CATEGORY_VALUES, types: [decision])
      create_list_field("Decision Status", DECISION_STATUS_VALUES, types: [decision])
      create_field("Approved Date", "date", types: [decision])

      { risk:, issue:, action:, decision: }
    end

    private

    def add_critical_priority
      return if IssuePriority.exists?(name: "Critical")

      max_position = IssuePriority.maximum(:position) || 0
      IssuePriority.create!(name: "Critical", position: max_position + 1)
    end

    def create_type(name, hexcode:)
      Type.find_or_create_by!(name:) do |t|
        t.is_default = true
        t.is_milestone = false
        t.is_in_roadmap = false
        t.color = Color.find_or_create_by!(hexcode:) { |c| c.name = name }
      end
    end

    def create_field(name, field_format, types:, editable: true)
      field = WorkPackageCustomField.find_or_create_by!(name:) do |cf|
        cf.field_format = field_format
        cf.is_for_all = true
        cf.is_filter = true
        cf.editable = editable
        cf.searchable = %w[string text].include?(field_format)
      end
      field.types = (field.types + types).uniq
      field.save!
      field
    end

    def create_list_field(name, values, types:)
      field = create_field(name, "list", types:)
      field.possible_values = values
      field.save!
      field
    end
  end
end
