class CreateOAndDProjectCustomField < ActiveRecord::Migration[8.1]
  # Same recipe as 20260908090000_create_account_manager_project_custom_field.rb
  # -- a plain, editable project attribute (shows on the project Overview
  # page like any other), not owned/gated by the payment_terms module.
  def up
    section = ProjectCustomFieldSection.find_by(name: "Project attributes")
    return unless section

    ProjectCustomField.find_or_create_by!(name: "O&D") do |cf|
      cf.field_format = "string"
      cf.is_for_all = true
      cf.is_filter = true
      cf.editable = true
      cf.searchable = true
      cf.custom_field_section = section
    end
  end

  def down
    ProjectCustomField.find_by(name: "O&D")&.destroy
  end
end
