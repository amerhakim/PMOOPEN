module PaymentTerms
  # One installment/invoice against a project's ContractLine. `value` is
  # always derived (percent of the parent line's component_value), never
  # entered directly, so it can't drift out of sync with the percentage --
  # recomputed on every save and whenever the parent line's value changes
  # (see ContractLine#payments and the before_save below).
  #
  # `expected_invoice_date` mirrors the linked milestone's due date when
  # one is set (kept in sync going forward by
  # WorkPackages::PaymentMilestoneSync on the milestone side); it's a
  # plain editable date otherwise.
  class Payment < ApplicationRecord
    self.table_name = "payment_terms_payments"

    belongs_to :contract_line, class_name: "PaymentTerms::ContractLine", inverse_of: :payments
    belongs_to :milestone, class_name: "WorkPackage", optional: true

    validates :description, presence: true
    validates :percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true

    validate :milestone_belongs_to_same_project

    before_save :recompute_value
    before_save :sync_expected_date_from_milestone

    def project
      contract_line.project
    end

    private

    def recompute_value
      self.value = if percent.present? && contract_line&.component_value.present?
                     (contract_line.component_value.to_f * percent.to_f / 100.0).round(2)
                   end
    end

    def sync_expected_date_from_milestone
      self.expected_invoice_date = milestone.due_date if milestone.present?
    end

    def milestone_belongs_to_same_project
      return if milestone.blank? || contract_line.blank?
      return if milestone.project_id == contract_line.project_id

      errors.add(:milestone, :invalid)
    end
  end
end
