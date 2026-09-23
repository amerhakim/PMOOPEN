class AddVendorManagementRoles < ActiveRecord::Migration[8.1]
  # New roles this module introduces (REQ-SEC-01), same pattern as
  # 20260901130000_add_pmo_governance_roles.rb -- ProjectRole, next free
  # `position` values (20 was the previous max).
  ROLES = [
    { name: "Procurement Manager", position: 21 },
    { name: "Finance", position: 22 }
  ].freeze

  def up
    ROLES.each do |role_data|
      next if Role.exists?(name: role_data[:name])

      ProjectRole.create!(
        name: role_data[:name],
        position: role_data[:position],
        builtin: Role::NON_BUILTIN
      )
    end
  end

  def down
    Role.where(name: ROLES.map { |r| r[:name] }).destroy_all
  end
end
