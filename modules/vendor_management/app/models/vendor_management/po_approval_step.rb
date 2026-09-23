module VendorManagement
  class PoApprovalStep < ApplicationRecord
    self.table_name = "vendor_management_po_approval_steps"

    STATUSES = %w[pending approved rejected].freeze

    belongs_to :purchase_order, class_name: "VendorManagement::PurchaseOrder", inverse_of: :po_approval_steps

    validates :approver_title, presence: true
    validates :status, inclusion: { in: STATUSES }

    def pending?
      status == "pending"
    end
  end
end
