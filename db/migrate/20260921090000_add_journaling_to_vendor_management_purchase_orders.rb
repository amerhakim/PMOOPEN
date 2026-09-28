class AddJournalingToVendorManagementPurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :vendor_management_purchase_orders, :submitted_by, foreign_key: { to_table: :users }, null: true

    # Minimal snapshot table for VendorManagement::PurchaseOrder's own
    # acts_as_journalized wiring -- only "status" is tracked for now.
    # No journal_id column here on purpose: the relationship is the
    # OPPOSITE direction from what a naive copy of a belongs_to-style
    # journal table (e.g. custom_comment_journals) would suggest --
    # journals.data_id/data_type point polymorphically AT this table's
    # own id, this table never points back at journals (confirmed by
    # reading the real, live news_journals schema: it has no journal_id
    # column at all, just its own plain id used as journals.data_id).
    # Journal::BaseJournal.journaled_attributes derives tracked columns
    # directly from whatever real columns exist here, so it's safe to
    # track a subset rather than mirroring every PurchaseOrder column --
    # extend later if the notification/activity-feed work needs more.
    create_table :vendor_management_purchase_order_journals do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.string :status
    end
  end
end
