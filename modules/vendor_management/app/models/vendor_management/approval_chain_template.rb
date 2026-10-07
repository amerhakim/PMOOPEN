module VendorManagement
  # A named, ordered sequence of approval steps (REQ-PO-06) -- configured
  # here BEFORE any PO is submitted, per the user's explicit decision.
  # `project` is nullable: nil means the company-wide default, which is
  # the only kind Phase 3's UI manages (find_or_create a singleton).
  class ApprovalChainTemplate < ApplicationRecord
    self.table_name = "vendor_management_approval_chain_templates"

    belongs_to :project, optional: true
    has_many :approval_step_definitions,
             -> { order(:sequence) },
             class_name: "VendorManagement::ApprovalStepDefinition",
             foreign_key: "approval_chain_template_id",
             dependent: :destroy,
             inverse_of: :approval_chain_template

    validates :name, presence: true

    def self.default_for(project)
      where(project_id: project&.id).first || where(project_id: nil).first
    end

    def self.company_default
      find_or_create_by!(project_id: nil) { |t| t.name = "Default Approval Chain" }
    end
  end
end
