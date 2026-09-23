class BackfillDurationBasedEstimatedHours < ActiveRecord::Migration[8.1]
  # One-time backfill for WorkPackages::DurationBasedEstimatedHours,
  # which only fires on future saves. Existing work packages (notably
  # MS-Project-imported ones, which never had Work/estimated_hours set at
  # all) need it applied once so "Weighted by work" hierarchy progress
  # totals have something to weight by immediately, not just after the
  # next edit touches each row.
  def up
    execute("UPDATE work_packages SET estimated_hours = duration * 8 WHERE duration IS NOT NULL")

    # The raw UPDATE above doesn't cascade derived_done_ratio/derived
    # dates up the hierarchy -- only WorkPackages::UpdateAncestorsService
    # (normally triggered by WorkPackages::UpdateService on a real edit,
    # which nothing calls for a bulk backfill) does that. Re-run it once
    # per leaf work package so every ancestor's derived attributes catch
    # up with the newly-populated Work values in one pass.
    system_user = User.system
    attrs = %i[done_ratio estimated_hours start_date due_date duration]

    WorkPackage.where.missing(:children).find_each do |leaf|
      WorkPackages::UpdateAncestorsService.new(user: system_user, work_package: leaf).call(attrs)
    end
  end

  def down
    # Not meaningfully reversible -- the point is Work is now always
    # derived from Duration going forward, there's no prior value to
    # restore to.
  end
end
