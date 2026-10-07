class CreateVendorManagementVendorTables < ActiveRecord::Migration[8.1]
  def change
    create_table :vendor_management_vendors do |t|
      t.string :name, null: false
      t.string :cr_number
      t.string :country
      t.string :contact_name
      t.string :contact_email
      t.string :contact_phone
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    # A vendor can carry more than one category at once (REQ-VEN-04, e.g.
    # a vendor that sells both hardware and software licenses) -- a real
    # join table rather than a serialized/joined-string column, so each
    # category stays individually queryable.
    create_table :vendor_management_vendor_categories do |t|
      t.references :vendor, null: false, foreign_key: { to_table: :vendor_management_vendors }
      t.string :category, null: false

      t.timestamps
    end
    add_index :vendor_management_vendor_categories, %i[vendor_id category],
              unique: true, name: "index_vm_vendor_categories_on_vendor_and_category"
  end
end
