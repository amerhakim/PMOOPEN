class FixDurationHoursCallbackTiming < ActiveRecord::Migration[8.1]
  # 20260914090000 still didn't stick: WorkPackages::DurationBasedEstimatedHours
  # used before_save, but OpenProject's service/contract layer validates
  # the model (checking for Remaining work) *before* ever calling save --
  # before_save never got a chance to run at all, since the contract
  # already rejected the record first. Moved to before_validation (which
  # WorkPackage#valid? triggers, and the contract does call that), see
  # the concern's own comment for the full explanation. Re-running the
  # exact same backfill here now that the hook actually fires early
  # enough.
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
