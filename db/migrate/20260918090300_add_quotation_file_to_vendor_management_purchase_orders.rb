class AddQuotationFileToVendorManagementPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_management_purchase_orders, :quotation_file_filename, :string
    add_column :vendor_management_purchase_orders, :quotation_file_content_type, :string
    add_column :vendor_management_purchase_orders, :quotation_file_data, :binary
  end
end
