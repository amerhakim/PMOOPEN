class CreateVendorManagementPoTables < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_management_purchase_orders do |t|
      t.references :project, null: false, foreign_key: true
      t.references :vendor, null: false, foreign_key: { to_table: :vendor_management_vendors }
      t.string :po_number, null: false
      t.string :quotation_ref_no
      t.date :issue_date
      t.string :currency, null: false, default: "QAR"
      t.decimal :total_value, precision: 15, scale: 2, default: "0.0", null: false
      t.string :status, null: false, default: "draft"
      t.date :expected_end_date
      t.text :payment_terms
      t.text :special_note
      t.boolean :is_non_cancellable, null: false, default: false
      t.string :end_user_name
      t.string :end_user_address
      t.string :end_user_contact_name
      t.string :end_user_contact_phone
      t.string :end_user_contact_email
      t.string :incoterm
      t.string :delivery_address
      t.string :delivery_contact

      t.timestamps
    end
    add_index :vendor_management_purchase_orders, %i[project_id po_number], unique: true

    create_table :vendor_management_po_line_items do |t|
      t.references :purchase_order, null: false, foreign_key: { to_table: :vendor_management_purchase_orders }
      t.string :part_no
      t.text :description, null: false
      t.string :item_type, null: false, default: "hardware"
      t.decimal :quantity, precision: 15, scale: 2, null: false
      t.decimal :unit_price, precision: 15, scale: 2, null: false
      t.decimal :line_total, precision: 15, scale: 2, default: "0.0", null: false
      t.date :start_date
      t.date :end_date
      # Populated once hardware delivery tracking ships (a later phase) --
      # left at 0 for every line item until then, not derived by anything
      # yet.
      t.decimal :delivered_qty, precision: 15, scale: 2, default: "0.0", null: false

      t.timestamps
    end
  end
end
