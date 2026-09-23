module PaymentTerms
  # One pricing pool within a project's contract (e.g. "Implementation",
  # "Support Year 1") -- a project can have several, each with its own
  # value, since a real contract often bundles components billed on
  # different terms (e.g. a fixed implementation price plus separately
  # priced support years).
  class ContractLine < ApplicationRecord
    self.table_name = "payment_terms_contract_lines"

    belongs_to :project
    has_many :payments,
             class_name: "PaymentTerms::Payment",
             foreign_key: "contract_line_id",
             dependent: :destroy,
             inverse_of: :contract_line

    validates :name, presence: true
    validates :component_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    after_save :recompute_payment_values, if: :saved_change_to_component_value?

    def percent_allocated
      payments.sum { |payment| payment.percent.to_f }
    end

    private

    def recompute_payment_values
      payments.find_each(&:save)
    end
  end
end
