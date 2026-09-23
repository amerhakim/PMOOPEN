module RaidLog
  # Deterministic risk score = Probability weight x Impact weight, matching
  # the 1..12 range implied by the Low/Medium/High probability and
  # Low/Medium/High/Critical impact scales used in the RAID log's Risk Log.
  class RiskScoreService
    PROBABILITY_WEIGHTS = { "Low" => 1, "Medium" => 2, "High" => 3 }.freeze
    IMPACT_WEIGHTS = { "Low" => 1, "Medium" => 2, "High" => 3, "Critical" => 4 }.freeze

    def self.call(probability:, impact:)
      new(probability:, impact:).call
    end

    def initialize(probability:, impact:)
      @probability = probability
      @impact = impact
    end

    def call
      p_weight = PROBABILITY_WEIGHTS[@probability]
      i_weight = IMPACT_WEIGHTS[@impact]
      return nil if p_weight.nil? || i_weight.nil?

      p_weight * i_weight
    end
  end
end
