# frozen_string_literal: true

# Read-only "expected completion" column: a purely date-based percentage
# (today vs. start/due date range) computed by
# WorkPackages::ExpectedCompletion#expected_completion. Unlike
# Predecessors/Successors this needs no client-side editing logic --  the
# value is simply returned by the API like any other computed property.
class Queries::WorkPackages::Selects::ExpectedCompletionSelect < Queries::WorkPackages::Selects::WorkPackageSelect
  def self.instances(_context = nil)
    [new(:expected_completion, sortable: false, groupable: false)]
  end

  def caption
    "Expected completion"
  end
end
