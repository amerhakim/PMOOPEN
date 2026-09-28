module VendorManagement
  class ApprovalStepDefinition < ApplicationRecord
    self.table_name = "vendor_management_approval_step_definitions"

    belongs_to :approval_chain_template, class_name: "VendorManagement::ApprovalChainTemplate",
                                          inverse_of: :approval_step_definitions
    belongs_to :role, optional: true

    validates :approver_title, presence: true
    validates :sequence, numericality: { only_integer: true, greater_than: 0 }
  end
end
