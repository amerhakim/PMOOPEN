module VendorManagement
  # A planned payment to the vendor, read from the PO's payment terms.
  class PoInstallment < ApplicationRecord
    self.table_name = "vendor_management_po_installments"

    belongs_to :purchase_order, class_name: "VendorManagement::PurchaseOrder", inverse_of: :po_installments

    validates :description, presence: true
    validates :amount, numericality: { greater_than_or_equal_to: 0 }
  end
end
