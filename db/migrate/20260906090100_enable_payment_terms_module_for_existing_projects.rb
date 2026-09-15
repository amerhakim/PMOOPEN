class EnablePaymentTermsModuleForExistingProjects < ActiveRecord::Migration[8.1]
  def up
    Project.find_each do |project|
      next if project.enabled_module_names.include?("payment_terms")

      project.enabled_module_names += ["payment_terms"]
      project.save!
    end
  end

  def down
    Project.find_each do |project|
      project.enabled_module_names -= ["payment_terms"]
      project.save!
    end
  end
end
