module WorkPackages
  # Keeps every linked PaymentTerms::Payment#expected_invoice_date mirroring
  # its milestone's due date, so a PM doesn't have to manually re-date
  # payments every time a milestone slips. The other direction (payment ->
  # milestone, on link creation/change) is handled in
  # PaymentTerms::Payment#sync_expected_date_from_milestone.
  module PaymentMilestoneSync
    extend ActiveSupport::Concern

    included do
      after_save :payment_terms_sync_linked_payments, if: :payment_terms_milestone_date_changed?
    end

    private

    def payment_terms_milestone_date_changed?
      type&.is_milestone? && saved_change_to_due_date?
    end

    def payment_terms_sync_linked_payments
      PaymentTerms::Payment.where(milestone_id: id).find_each do |payment|
        next if payment.expected_invoice_date == due_date

        payment.update_column(:expected_invoice_date, due_date)
      end
    end
  end
end
