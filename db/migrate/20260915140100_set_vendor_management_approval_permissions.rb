class SetVendorManagementApprovalPermissions < ActiveRecord::Migration[8.1]
  # v1 stand-in: the BRD's own approval chain names Director/DGM/GM-level
  # titles that have no corresponding OpenProject role, so
  # manage_vendor_management_approvals (act on an approval step) is
  # granted to the most senior PMO-side roles already in this instance
  # rather than inventing new ones that would sit unused. Procurement
  # Manager is included too since they're the ones most likely to need to
  # push a PO through if a named approver is unavailable.
  ROLES = ["Procurement Manager", "PMO Director", "Executive / Sponsor"].freeze

  def up
    ROLES.each { |name| add_permission(name) }
  end

  def down
    ROLES.each do |name|
      role = Role.find_by(name:)
      next unless role

      role.permissions -= %w[manage_vendor_management_approvals]
      role.save!
    end
  end

  private

  def add_permission(role_name)
    role = Role.find_by(name: role_name)
    return unless role

    role.permissions = (role.permissions + ["manage_vendor_management_approvals"]).uniq
    role.save!
  end
end
