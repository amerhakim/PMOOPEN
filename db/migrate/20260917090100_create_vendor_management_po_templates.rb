class CreateVendorManagementPoTemplates < ActiveRecord::Migration[8.1]
  # Effectively a singleton config row (see VendorManagement::PoTemplate.current)
  # holding the editable header/footer text shown on every PO PDF export.
  # Plain text, not HTML -- the reference document's header/footer are
  # fixed styling (bold, centered), only the text itself needs to be
  # editable, and plain text avoids an HTML-injection surface in a
  # PDF-rendering context.
  def change
    create_table :vendor_management_po_templates do |t|
      t.text :header_text
      t.text :footer_text

      t.timestamps
    end
  end
end
