class SetVendorManagementProjectPermissions < ActiveRecord::Migration[8.1]
  # Procurement Manager and Finance already exist as roles (Phase 1) --
  # this migration just grants them (and the relevant PMO roles) the new
  # per-project view/edit_vendor_management permissions that Purchase
  # Orders need, same pattern as
  # 20260906090200_set_payment_terms_role_permissions.rb.
  EDIT_AND_VIEW = ["Procurement Manager"].freeze
  VIEW_ONLY = [
    "Finance", "Project Manager", "Portfolio Manager", "Program Manager",
    "PMO Director", "Executive / Sponsor"
  ].freeze

  def up
    EDIT_AND_VIEW.each { |name| add_permissions(name, %w[view_vendor_management edit_vendor_management]) }
    VIEW_ONLY.each { |name| add_permissions(name, %w[view_vendor_management]) }
  end

  def down
    (EDIT_AND_VIEW + VIEW_ONLY).each do |name|
      role = Role.find_by(name:)
      next unless role

      role.permissions -= %w[view_vendor_management edit_vendor_management]
      role.save!
    end
  end

  private

  def add_permissions(role_name, permissions)
    role = Role.find_by(name: role_name)
    return unless role

    role.permissions = (role.permissions + permissions).uniq
    role.save!
  end
end
