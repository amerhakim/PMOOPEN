module VendorManagement
  # Company-wide vendor directory (REQ-VEN-01/02/04) -- NOT scoped to a
  # project. A vendor gets linked to individual projects only indirectly,
  # through the Purchase Orders raised against it (a later phase), which
  # is why this model carries no project_id at all.
  class Vendor < ApplicationRecord
    self.table_name = "vendor_management_vendors"

    CATEGORIES = ["Hardware", "Software", "Service", "Consulting"].freeze
    STATUSES = %w[active inactive].freeze

    has_many :vendor_categories,
             class_name: "VendorManagement::VendorCategory",
             dependent: :destroy,
             inverse_of: :vendor

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    def category_list
      vendor_categories.pluck(:category)
    end

    def category_list=(values)
      selected = Array(values).reject(&:blank?) & CATEGORIES
      self.vendor_categories = selected.map { |c| VendorCategory.new(category: c) }
    end
  end
end
