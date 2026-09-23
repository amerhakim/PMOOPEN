module VendorManagement
  class VendorCategory < ApplicationRecord
    self.table_name = "vendor_management_vendor_categories"

    belongs_to :vendor, class_name: "VendorManagement::Vendor", inverse_of: :vendor_categories

    validates :category, presence: true, inclusion: { in: Vendor::CATEGORIES }
  end
end
