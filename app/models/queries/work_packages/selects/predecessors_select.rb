# frozen_string_literal: true

# Non-Enterprise, editable "Predecessors" column for the work package table
# (visible in the Gantt/Timeline view's left-hand list). Unlike the built-in
# Enterprise relation columns (Queries::WorkPackages::Selects::RelationSelect
# and subclasses), which are read-only/expand-only, this column's value is
# handled entirely client-side by PredecessorsEditFieldComponent, which
# parses MS-Project-style predecessor text ("3", "7SS-1", "12FF+2") and
# calls the relations API directly.
class Queries::WorkPackages::Selects::PredecessorsSelect < Queries::WorkPackages::Selects::WorkPackageSelect
  def self.instances(_context = nil)
    [new(:predecessors, sortable: false, groupable: false)]
  end

  def caption
    "Predecessors"
  end
end
