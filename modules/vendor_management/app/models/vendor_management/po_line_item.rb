module VendorManagement
  class PoLineItem < ApplicationRecord
    self.table_name = "vendor_management_po_line_items"

    ITEM_TYPES = %w[hardware software_license software_subscription service other].freeze

    belongs_to :purchase_order, class_name: "VendorManagement::PurchaseOrder", inverse_of: :po_line_items

    validates :description, presence: true
    validates :item_type, inclusion: { in: ITEM_TYPES }
    validates :quantity, numericality: { greater_than: 0 }
    validates :unit_price, numericality: { greater_than_or_equal_to: 0 }

    before_save :recompute_line_total
    after_save :recompute_purchase_order_total, if: :saved_change_to_line_total?
    after_save :recompute_purchase_order_delivery_status,
               if: -> { saved_change_to_delivered_to_qds? || saved_change_to_delivered_to_customer? }
    after_destroy :recompute_purchase_order_total
    after_destroy :recompute_purchase_order_delivery_status

    def project
      purchase_order.project
    end

    private

    def recompute_line_total
      self.line_total = (quantity.to_f * unit_price.to_f).round(2)
    end

    def recompute_purchase_order_total
      purchase_order.recompute_total_value!
    end

    def recompute_purchase_order_delivery_status
      purchase_order.recompute_delivery_status!
    end
  end
end
