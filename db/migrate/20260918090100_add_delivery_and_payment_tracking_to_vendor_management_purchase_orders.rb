class AddDeliveryAndPaymentTrackingToVendorManagementPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_management_purchase_orders, :order_description, :text
    add_column :vendor_management_purchase_orders, :delivery_status_qds, :string, null: false, default: "not_delivered"
    add_column :vendor_management_purchase_orders, :delivery_status_customer, :string, null: false, default: "not_delivered"
    add_column :vendor_management_purchase_orders, :total_paid, :decimal, precision: 15, scale: 2, null: false, default: 0
    add_column :vendor_management_purchase_orders, :remaining_in_po, :decimal, precision: 15, scale: 2, null: false, default: 0

    add_column :vendor_management_po_line_items, :delivered_to_qds, :boolean, null: false, default: false
    add_column :vendor_management_po_line_items, :delivered_to_customer, :boolean, null: false, default: false
  end
end
