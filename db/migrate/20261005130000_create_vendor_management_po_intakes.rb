class CreateVendorManagementPoIntakes < ActiveRecord::Migration[8.1]
  def change
    # Staging row for "create purchase orders from a file": the uploaded
    # PDF/Excel, what the AI read out of it, and where the processing is.
    create_table :vendor_management_po_intakes do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :source_kind, null: false
      t.string :source_filename, null: false
      t.string :source_content_type
      t.binary :source_data, null: false
      t.string :status, null: false, default: "queued"
      t.string :stage
      t.text :result
      t.text :error_message
      t.timestamps
    end

    # The vendor payment schedule read from a PO's payment terms. Planned
    # installments only -- what was actually paid stays in po_payments.
    create_table :vendor_management_po_installments do |t|
      t.references :purchase_order, null: false, foreign_key: { to_table: :vendor_management_purchase_orders }
      t.integer :position, null: false, default: 0
      t.string :description, null: false
      t.decimal :percent, precision: 7, scale: 3
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.date :due_on
      t.timestamps
    end
  end
end
