module RaidLog
  # Recomputes the Risk type's "Score" custom field from "Probability" and
  # "Impact" whenever a work package is saved. Writes the CustomValue
  # directly (not via work_package.save) so this cannot recurse into its own
  # after_save callback.
  module ScoreCalculation
    extend ActiveSupport::Concern

    included do
      after_save :raid_log_recompute_score, if: :raid_log_risk_type?
    end

    private

    def raid_log_risk_type?
      type&.name == "Risk"
    end

    def raid_log_recompute_score
      probability_field = RaidLog::CustomFields.probability_field
      impact_field = RaidLog::CustomFields.impact_field
      score_field = RaidLog::CustomFields.score_field
      return unless probability_field && impact_field && score_field

      score = RaidLog::RiskScoreService.call(
        probability: typed_custom_value_for(probability_field),
        impact: typed_custom_value_for(impact_field)
      )

      existing = custom_value_for(score_field)
      return if existing&.value.to_s == score.to_s

      if score.nil?
        existing&.destroy
      else
        (existing || custom_values.build(custom_field: score_field)).update!(value: score)
      end
    end
  end
end
