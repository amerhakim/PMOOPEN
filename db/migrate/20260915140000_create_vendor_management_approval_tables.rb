class CreateVendorManagementApprovalTables < ActiveRecord::Migration[8.1]
  def change
    # project_id nullable: NULL means the company-wide default template.
    # A per-project override could be added later without a schema
    # change, but Phase 3 only ever manages the single default (v1 scope
    # per the user's "one screen" ask, not a per-project template picker).
    create_table :vendor_management_approval_chain_templates do |t|
      t.references :project, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    create_table :vendor_management_approval_step_definitions do |t|
      t.references :approval_chain_template, null: false,
                    foreign_key: { to_table: :vendor_management_approval_chain_templates }
      t.integer :sequence, null: false
      t.string :approver_title, null: false
      t.references :role, foreign_key: true

      t.timestamps
    end

    # A snapshot of the template's steps at the moment a specific PO was
    # first submitted -- never a live reference to the step definitions
    # above, so editing the template later never rewrites history on POs
    # already in flight (same reasoning as payment_terms_payments
    # snapshotting `value` instead of recomputing it at read time).
    create_table :vendor_management_po_approval_steps do |t|
      t.references :purchase_order, null: false,
                    foreign_key: { to_table: :vendor_management_purchase_orders }
      t.integer :sequence, null: false
      t.string :approver_title, null: false
      t.string :approver_name
      t.string :status, null: false, default: "pending"
      t.datetime :signed_at

      t.timestamps
    end
  end
end
