class AddLayoutJsonToVendorManagementPoTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :vendor_management_po_templates, :layout_json, :text
  end
end
