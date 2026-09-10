class AlignPmoRolesWithFinancialGovernance < ActiveRecord::Migration[8.1]
  # Resource Management vs Financial Management separation, per the
  # governance model: engineers see only their own tasks/time, department/
  # functional managers own resourcing (allocation, standard cost rates,
  # timesheets) without seeing project P&L, project managers see
  # budget/actual/planned cost totals without per-person rate data, and
  # PMO Director / Executive-Sponsor get full financial visibility
  # (budgets, itemized cost entries, hourly rates).
  #
  # Relies on modules/budgets and modules/costs already gating the
  # itemized, rate-derived numbers behind view_cost_rates/view_cost_entries
  # separately from the aggregate budget totals behind view_budgets (see
  # modules/budgets/app/views/budgets/show.html.erb and
  # modules/budgets/app/views/budgets/items/_labor_budget_item.html.erb) --
  # that's what lets a Project Manager see "Actual cost: 12,400 QAR" on a
  # budget without being able to see that it's Ahmed's 40 hours at 150/hr.
  #
  # Project Manager, Portfolio Manager, Program Manager and Technical Team
  # Member are intentionally left untouched -- their existing permission
  # sets (from db/migrate/20260901130000_add_pmo_governance_roles.rb)
  # already match this model.
  ADDITIONS = {
    "PMO Director" => %w[
      view_budgets edit_budgets view_cost_entries view_cost_rates
      view_hourly_rates view_time_entries
    ],
    "Functional Manager" => %w[
      view_time_entries edit_time_entries view_hourly_rates edit_hourly_rates
    ],
    "Executive / Sponsor" => %w[
      view_hourly_rates view_cost_rates
    ]
  }.freeze

  def up
    ADDITIONS.each do |role_name, permissions_to_add|
      role = Role.find_by(name: role_name)
      next unless role

      role.permissions = (role.permissions + permissions_to_add).uniq
      role.save!
    end
  end

  def down
    ADDITIONS.each do |role_name, permissions_to_remove|
      role = Role.find_by(name: role_name)
      next unless role

      role.permissions -= permissions_to_remove
      role.save!
    end
  end
end
