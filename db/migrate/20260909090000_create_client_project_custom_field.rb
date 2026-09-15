class CreateClientProjectCustomField < ActiveRecord::Migration[8.1]
  # Same pattern as Account Manager (20260908090000) -- the redesigned PMO
  # Dashboard card shows the client company name under the project name.
  def up
    section = ProjectCustomFieldSection.find_by(name: "Project attributes")
    return unless section

    ProjectCustomField.find_or_create_by!(name: "Client") do |cf|
      cf.field_format = "string"
      cf.is_for_all = true
      cf.is_filter = true
      cf.editable = true
      cf.searchable = true
      cf.custom_field_section = section
    end
  end

  def down
    ProjectCustomField.find_by(name: "Client")&.destroy
  end
end
