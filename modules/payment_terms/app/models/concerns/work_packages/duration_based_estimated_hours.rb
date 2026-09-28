module WorkPackages
  # Per the user: Work (estimated_hours) should always be driven by the
  # schedule, never entered by hand -- every work package with both a
  # start and due date gets Work = Duration (working days) x 8 hours,
  # recalculated on every save so it stays in sync whenever the dates
  # change. This is also exactly what "Weighted by work" hierarchy
  # progress totals key off of (see Administration > Work packages >
  # Progress tracking), so a summary task's rolled-up Actual % now
  # genuinely reflects how long each child spans, not just how many of
  # them happen to be marked done.
  #
  # Deliberately instance-wide (every project, every type) and always
  # wins over a manually-typed Work value, per the user's explicit
  # choice -- this is NOT a "fill in if blank" default.
  #
  # Also derives Remaining work from the new Work value + the current
  # %Complete (remaining = work x (1 - %complete/100)) whenever %Complete
  # is set. Not optional: in "Work-based" progress tracking mode (see
  # Progress tracking above), Work/Remaining work/%Complete are a
  # mutually-consistent triangle -- WorkPackages::BaseContract rejects a
  # save where Work and %Complete are both present but Remaining work is
  # missing or doesn't recompute back to the same %Complete. Found this
  # the hard way: the model-level `estimated_hours` write above silently
  # never persisted on plenty of existing work packages (the validation
  # failure means WorkPackages::UpdateService returns success: false, no
  # exception raised) until this was added too.
  #
  # `before_validation`, NOT `before_save`: OpenProject's service objects
  # (WorkPackages::UpdateService etc.) run the contract's validation
  # against the model *before* ever calling save -- a before_save
  # callback never gets a chance to run at all if the contract already
  # rejected the record for missing Remaining work. before_validation
  # runs as part of WorkPackage#valid?, which the contract does trigger,
  # early enough for the derived value to be in place when the contract
  # actually checks it.
  module DurationBasedEstimatedHours
    extend ActiveSupport::Concern

    HOURS_PER_DAY = 8

    included do
      before_validation :set_estimated_hours_from_duration
    end

    private

    def set_estimated_hours_from_duration
      return if duration.nil?

      self.estimated_hours = duration * HOURS_PER_DAY
      self.remaining_hours = estimated_hours * (1 - done_ratio / 100.0) if done_ratio.present?
    end
  end
end
