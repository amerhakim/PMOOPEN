class AddSectionLabelToVendorManagementPoLineItems < ActiveRecord::Migration[8.1]
  # Groups line items into labeled sections on the PO PDF (e.g. "Optional:
  # Thales CipherTrust Data Security Platform - Production", "Shipping &
  # Cargo Charges") -- nil/blank means the item belongs to the main,
  # unlabeled section. Matches the real reference PO document the user
  # attached (QDS-CMSG-335-671.pdf).
  def change
    add_column :vendor_management_po_line_items, :section_label, :string
  end
end
