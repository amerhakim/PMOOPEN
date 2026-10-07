module VendorManagement
  # A single payment made to the vendor against a PO's total value --
  # an open, repeatable list (not a fixed "first/second invoice" pair)
  # so procurement can record however many installments actually happen.
  # PurchaseOrder#total_paid/#remaining_in_po are cached sums recomputed
  # whenever a payment is added or removed (see the callbacks below).
  class PoPayment < ApplicationRecord
    self.table_name = "vendor_management_po_payments"

    belongs_to :purchase_order, class_name: "VendorManagement::PurchaseOrder", inverse_of: :po_payments

    validates :amount, numericality: { greater_than: 0 }
    validates :paid_on, presence: true

    after_save :recompute_purchase_order_totals
    after_destroy :recompute_purchase_order_totals

    private

    def recompute_purchase_order_totals
      purchase_order.recompute_payment_totals!
    end
  end
end
