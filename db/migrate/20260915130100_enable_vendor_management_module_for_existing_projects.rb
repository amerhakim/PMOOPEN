class EnableVendorManagementModuleForExistingProjects < ActiveRecord::Migration[8.1]
  def up
    Project.find_each do |project|
      next if project.enabled_module_names.include?("vendor_management")

      project.enabled_module_names += ["vendor_management"]
      project.save!
    end
  end

  def down
    Project.find_each do |project|
      next unless project.enabled_module_names.include?("vendor_management")

      project.enabled_module_names -= ["vendor_management"]
      project.save!
    end
  end
end
