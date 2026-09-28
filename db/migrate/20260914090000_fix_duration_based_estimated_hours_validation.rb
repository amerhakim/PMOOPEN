class FixDurationBasedEstimatedHoursValidation < ActiveRecord::Migration[8.1]
  # 20260914080000's backfill silently didn't stick for any work package
  # that also had a %Complete value: WorkPackages::DurationBasedEstimatedHours
  # only set estimated_hours (Work), and OpenProject's "Work-based"
  # progress tracking mode requires Remaining work to be set (and
  # mathematically consistent) whenever Work and %Complete are both
  # present -- the raw UPDATE bypassed that check, but the
  # WorkPackages::UpdateAncestorsService calls that were supposed to
  # cascade derived_done_ratio up the hierarchy went through real
  # validation and failed there silently (ServiceResult#success? false,
  # no exception), so every ancestor's derived_done_ratio stayed nil
  # despite looking like the backfill had run cleanly.
  #
  # The concern now derives Remaining work too (see its comment for the
  # formula), so a real, validated save finally succeeds. This migration
  # re-runs that save for every already-imported work package with a
  # duration, this time through WorkPackages::UpdateService (real
  # validation, real ancestor cascade), not a raw UPDATE.
  def up
    admin = User.find_by(admin: true)
    return unless admin

    WorkPackage.where.not(duration: nil).find_each do |wp|
      WorkPackages::UpdateService.new(user: admin, model: wp).call(done_ratio: wp.done_ratio)
    end
  end

  def down
    # Not meaningfully reversible -- see 20260914080000.
  end
end
