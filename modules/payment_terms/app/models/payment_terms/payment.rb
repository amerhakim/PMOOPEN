module PaymentTerms
  # One installment/invoice against a project's ContractLine. `percent`
  # and `value` are always kept in sync with each other and with the
  # parent line's component_value -- whichever one was actually typed
  # into on the form (see `entered_field`, set from the form's hidden
  # field, itself kept up to date by the live percent<->amount JS in
  # _payment_form.html.erb) is authoritative for a given save, and the
  # other one is recomputed from it. Also recomputed (percent-driven,
  # the long-standing default) whenever the parent line's own value
  # changes (see ContractLine#recompute_payment_values).
  #
  # `expected_invoice_date` mirrors the linked milestone's due date when
  # one is set (kept in sync going forward by
  # WorkPackages::PaymentMilestoneSync on the milestone side); it's a
  # plain editable date otherwise.
  class Payment < ApplicationRecord
    self.table_name = "payment_terms_payments"

    belongs_to :contract_line, class_name: "PaymentTerms::ContractLine", inverse_of: :payments
    belongs_to :milestone, class_name: "WorkPackage", optional: true

    # Not persisted -- "percent" (the long-standing default) or "value",
    # set from the form's hidden field to say which box the user actually
    # typed a new number into on THIS submission, so #recompute_value
    # knows which direction to derive the other one in. Never trusted
    # for anything except that direction: whichever field it names still
    # goes through the exact same validations as before.
    attr_accessor :entered_field

    validates :description, presence: true
    validates :percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
    validates :value, numericality: { greater_than: 0 }, allow_nil: true

    validate :milestone_belongs_to_same_project

    before_save :recompute_value
    before_save :sync_expected_date_from_milestone

    def project
      contract_line.project
    end

    private

    def recompute_value
      component_value = contract_line&.component_value

      if component_value.blank? || component_value.to_f.zero?
        self.value = nil
        return
      end

      if entered_field == "value" && value.present?
        self.percent = (value.to_f / component_value.to_f * 100).round(2)
      elsif percent.present?
        self.value = (component_value.to_f * percent.to_f / 100.0).round(2)
      else
        self.value = nil
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
