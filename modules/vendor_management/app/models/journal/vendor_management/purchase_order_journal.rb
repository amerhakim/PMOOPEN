# `Journal` is a real ActiveRecord class in core (app/models/journal.rb),
# not a namespace-only module -- reopening it with `class Journal`, not
# `module Journal`, or Ruby raises "Journal is not a module (TypeError)".
class Journal
  module VendorManagement
    # Per-model journal snapshot for VendorManagement::PurchaseOrder --
    # resolved by convention via Acts::Journalized::DataClass#journal_class
    # ("Journal::#{base_class.name}Journal"), mirroring how
    # Journal::NewsJournal/Journal::MeetingJournal work for their own
    # models. Table only carries "status" for now (see the migration
    # comment) -- Journal::BaseJournal derives tracked attributes from
    # this table's own real columns, so it's safe to extend later without
    # touching PurchaseOrder's own acts_as_journalized call.
    class PurchaseOrderJournal < Journal::BaseJournal
      self.table_name = "vendor_management_purchase_order_journals"
    end
  end
end
