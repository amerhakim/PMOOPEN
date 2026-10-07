class CreateVendorManagementDeliveryNotes < ActiveRecord::Migration[8.1]
  def change
    # Delivery notes (and other proof-of-delivery files) uploaded against a
    # project's purchase orders, or directly on the project. Stored as bytes
    # in the row, like a PO's quotation file.
    create_table :vendor_management_delivery_notes do |t|
      t.references :project, null: false, foreign_key: true
      t.references :purchase_order, null: true, foreign_key: { to_table: :vendor_management_purchase_orders, on_delete: :nullify }
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.string :filename, null: false
      t.string :content_type
      t.bigint :byte_size, null: false, default: 0
      t.binary :data, null: false
      t.timestamps
    end
  end
end
