class CreateVendorManagementPoPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_management_po_payments do |t|
      t.references :purchase_order, null: false, foreign_key: { to_table: :vendor_management_purchase_orders }
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.date :paid_on, null: false
      t.string :invoice_no
      t.text :note
      t.timestamps
    end
  end
end
