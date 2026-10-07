class AddDiscountToVendorManagementPurchaseOrders < ActiveRecord::Migration[8.0]
  def change
    # A discount printed in a quotation / PO, taken off the sum of the line items so that
    # the PO total equals the value of the document.
    add_column :vendor_management_purchase_orders, :discount, :decimal, precision: 15, scale: 2, null: false, default: 0
  end
end
