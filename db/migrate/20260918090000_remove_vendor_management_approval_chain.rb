class RemoveVendorManagementApprovalChain < ActiveRecord::Migration[8.1]
  def up
    drop_table :vendor_management_po_approval_steps, if_exists: true
    drop_table :vendor_management_approval_step_definitions, if_exists: true
    drop_table :vendor_management_approval_chain_templates, if_exists: true

    # The approval workflow is gone -- normalize any PO left mid-flow onto
    # the new, simpler status list (draft/active/closed/cancelled).
    execute <<~SQL.squish
      UPDATE vendor_management_purchase_orders SET status = 'active' WHERE status = 'approved';
      UPDATE vendor_management_purchase_orders SET status = 'draft' WHERE status = 'pending_approval';
    SQL
  end

  def down
    create_table :vendor_management_approval_chain_templates do |t|
      t.references :project, null: true, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :vendor_management_approval_step_definitions do |t|
      t.references :approval_chain_template, null: false, foreign_key: { to_table: :vendor_management_approval_chain_templates }
      t.integer :sequence, null: false
      t.string :approver_title, null: false
      t.references :role, null: true, foreign_key: true
      t.timestamps
    end

    create_table :vendor_management_po_approval_steps do |t|
      t.references :purchase_order, null: false, foreign_key: { to_table: :vendor_management_purchase_orders }
      t.integer :sequence, null: false
      t.string :approver_title, null: false
      t.string :status, null: false, default: "pending"
      t.string :approver_name
      t.datetime :signed_at
      t.timestamps
    end
  end
end
