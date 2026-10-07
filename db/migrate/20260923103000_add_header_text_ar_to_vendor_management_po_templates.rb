class AddHeaderTextArToVendorManagementPoTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_management_po_templates, :header_text_ar, :text
  end
end
