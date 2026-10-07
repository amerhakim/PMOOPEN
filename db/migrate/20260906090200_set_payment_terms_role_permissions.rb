class SetPaymentTermsRolePermissions < ActiveRecord::Migration[8.1]
  # Payment terms carry contract value -- restricted to the PM who
  # maintains them and their direct superiors in the PMO chain, per the
  # user's explicit call: Functional Manager and Technical Team Member get
  # neither permission (see modules/payment_terms/lib/payment_terms/engine.rb).
  EDIT_AND_VIEW = ["Project Manager"].freeze
  VIEW_ONLY = ["Portfolio Manager", "Program Manager", "PMO Director", "Executive / Sponsor"].freeze

  def up
    EDIT_AND_VIEW.each { |name| add_permissions(name, %w[view_payment_terms edit_payment_terms]) }
    VIEW_ONLY.each { |name| add_permissions(name, %w[view_payment_terms]) }
  end

  def down
    (EDIT_AND_VIEW + VIEW_ONLY).each do |name|
      role = Role.find_by(name:)
      next unless role

      role.permissions -= %w[view_payment_terms edit_payment_terms]
      role.save!
    end
  end

  private

  def add_permissions(role_name, permissions)
    role = Role.find_by(name: role_name)
    return unless role

    role.permissions = (role.permissions + permissions).uniq
    role.save!
  end
end
