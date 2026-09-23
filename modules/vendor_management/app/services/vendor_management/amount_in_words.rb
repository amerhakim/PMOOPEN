module VendorManagement
  # Spells out a PO's total value for the "Amount in Words" line on the
  # PDF export (REQ-PO-09), e.g. "Three Hundred Sixty Thousand Three
  # Hundred Forty Five US Dollars Only" -- matches the reference PO
  # document's own wording pattern (currency name + amount + "Only",
  # "and NN/100" inserted only when there is a fractional part).
  class AmountInWords
    CURRENCY_NAMES = {
      "QAR" => "Qatari Riyals",
      "SAR" => "Saudi Riyals",
      "OMR" => "Omani Rials",
      "USD" => "US Dollars"
    }.freeze

    ONES = %w[Zero One Two Three Four Five Six Seven Eight Nine Ten
              Eleven Twelve Thirteen Fourteen Fifteen Sixteen Seventeen Eighteen Nineteen].freeze
    TENS = %w[Zero Ten Twenty Thirty Forty Fifty Sixty Seventy Eighty Ninety].freeze
    SCALES = ["", "Thousand", "Million", "Billion", "Trillion"].freeze

    def initialize(value, currency)
      @value = value.to_f.round(2)
      @currency = currency
    end

    def call
      whole = @value.truncate
      fraction = ((@value - whole) * 100).round
      currency_name = CURRENCY_NAMES[@currency] || @currency
      words = number_to_words(whole)

      if fraction.zero?
        "#{words} #{currency_name} Only"
      else
        "#{words} #{currency_name} and #{format('%02d', fraction)}/100 Only"
      end
    end

    private

    def number_to_words(number)
      return "Zero" if number.zero?

      groups = []
      n = number
      while n.positive?
        groups << (n % 1000)
        n /= 1000
      end
      groups.reverse!

      chunks = groups.each_with_index.filter_map do |group, index|
        next if group.zero?

        scale = SCALES[groups.size - 1 - index]
        [three_digit_words(group), scale].reject(&:blank?).join(" ")
      end

      chunks.join(" ")
    end

    def three_digit_words(n)
      words = []
      if n >= 100
        words << "#{ONES[n / 100]} Hundred"
        n %= 100
      end
      if n >= 20
        tens_word = TENS[n / 10]
        n %= 10
        words << (n.zero? ? tens_word : "#{tens_word} #{ONES[n]}")
      elsif n.positive?
        words << ONES[n]
      end
      words.join(" ")
    end
  end
end
