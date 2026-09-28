# frozen_string_literal: true

# Companion to Queries::WorkPackages::Selects::PredecessorsSelect: the mirror
# image, showing/editing "precedes" relations (this work package's
# successors) instead of "follows" relations (predecessors). Same
# non-Enterprise, client-side-handled design.
class Queries::WorkPackages::Selects::SuccessorsSelect < Queries::WorkPackages::Selects::WorkPackageSelect
  def self.instances(_context = nil)
    [new(:successors, sortable: false, groupable: false)]
  end

  def caption
    "Successors"
  end
end
