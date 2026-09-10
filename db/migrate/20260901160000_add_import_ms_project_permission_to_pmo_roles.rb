class AddImportMsProjectPermissionToPmoRoles < ActiveRecord::Migration[8.1]
  ROLE_NAMES = [
    "PMO Director",
    "Portfolio Manager",
    "Program Manager",
    "Project Manager"
  ].freeze

  def up
    Role.where(name: ROLE_NAMES).find_each do |role|
      next if role.permissions.include?(:import_ms_project)

      role.permissions += [:import_ms_project]
      role.save!
    end
  end

  def down
    Role.where(name: ROLE_NAMES).find_each do |role|
      role.permissions -= [:import_ms_project]
      role.save!
    end
  end
end
