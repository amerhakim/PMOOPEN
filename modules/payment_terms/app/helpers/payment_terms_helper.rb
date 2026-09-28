module PaymentTermsHelper
  # Account Manager is its own project attribute (client-relationship
  # owner), deliberately separate from whoever holds the Project Manager
  # role -- see db/migrate/20260908090000_create_account_manager_project_custom_field.rb.
  def payment_terms_account_manager(project)
    field = ProjectCustomField.find_by(name: "Account Manager")
    return nil unless field

    project.custom_value_for(field)&.value
  end

  # Whoever holds the "Project Manager" role on this project (via a real
  # membership, not a project attribute) -- joins names with ", " on the
  # rare case a project has more than one.
  def payment_terms_project_manager(project)
    names = project.memberships
                    .joins(:roles)
                    .where(roles: { name: "Project Manager" })
                    .distinct
                    .map { |member| member.principal.name }

    names.join(", ").presence
  end

  # Green once collected, red once invoiced but still not collected,
  # left at the default text color while neither has happened yet. Uses
  # Primer's own color-fg-success/color-fg-danger utility classes (same
  # tokens Primer::Beta::Text's color: :success/:danger map to) rather
  # than hardcoded hex, so this adapts correctly under dark mode / high
  # contrast themes instead of a fixed color.
  def payment_row_color_class(payment)
    if payment.collected?
      "color-fg-success"
    elsif payment.invoiced?
      "color-fg-danger"
    else
      ""
    end
  end
end
