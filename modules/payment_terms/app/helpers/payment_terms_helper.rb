module PaymentTermsHelper
  # Account Manager is its own project attribute (client-relationship
  # owner), deliberately separate from whoever holds the Project Manager
  # role -- see db/migrate/20260908090000_create_account_manager_project_custom_field.rb.
  def payment_terms_account_manager(project)
    field = ProjectCustomField.find_by(name: "Account Manager")
    return nil unless field

    project.custom_value_for(field)&.value
  end
end
