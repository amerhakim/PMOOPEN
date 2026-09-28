class AddOAndDToVendorManagementPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_management_purchase_orders, :o_and_d, :string
    add_index :vendor_management_purchase_orders, :o_and_d
  end
end
