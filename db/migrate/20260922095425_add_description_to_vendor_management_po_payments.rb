class AddDescriptionToVendorManagementPoPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_management_po_payments, :description, :string
  end
end
