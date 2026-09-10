class CreateAccountManagerProjectCustomField < ActiveRecord::Migration[8.1]
  # Per the user: Account Manager is a distinct role from Project Manager
  # (client-relationship owner vs. delivery lead) and belongs on the
  # project itself, not derived from a PM role membership.
  def up
    section = ProjectCustomFieldSection.find_by(name: "Project attributes")
    return unless section

    ProjectCustomField.find_or_create_by!(name: "Account Manager") do |cf|
      cf.field_format = "string"
      cf.is_for_all = true
      cf.is_filter = true
      cf.editable = true
      cf.searchable = true
      cf.custom_field_section = section
    end
  end

  def down
    ProjectCustomField.find_by(name: "Account Manager")&.destroy
  end
end
