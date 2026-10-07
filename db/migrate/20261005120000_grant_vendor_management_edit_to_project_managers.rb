class GrantVendorManagementEditToProjectManagers < ActiveRecord::Migration[8.1]
  # Project and Program Managers raise their own purchase orders (and
  # vendors, see VendorManagementController): they already had
  # view_vendor_management, this adds edit_vendor_management. Same
  # pattern as 20260915130200_set_vendor_management_project_permissions.rb.
  ROLES = ["Project Manager", "Program Manager"].freeze

  def up
    ROLES.each do |name|
      role = Role.find_by(name:)
      next unless role

      role.permissions = (role.permissions + %w[view_vendor_management edit_vendor_management]).uniq
      role.save!
    end
  end

  def down
    ROLES.each do |name|
      role = Role.find_by(name:)
      next unless role

      role.permissions -= %w[edit_vendor_management]
      role.save!
    end
  end
end
