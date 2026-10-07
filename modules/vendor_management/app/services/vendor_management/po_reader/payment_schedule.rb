module VendorManagement
  module PoReader
    # Turns the supplier payment terms ("10% on signing ...", "60 Days Credit",
    # "Annual Payment for 3 Years (QAR 1,084,599.41)") into planned
    # installments with amounts and, where the terms allow it, due dates.
    class PaymentSchedule
      def initialize(installments:, total:, issue_date:, terms_text:)
        @raw = Array(installments)
        @total = total.to_f
        @issue_date = issue_date
        @terms = terms_text.to_s
      end

      # => { "installments" => [...], "warnings" => [...] }
      def call
        warnings = []
        rows = @raw.filter_map { |r| normalize(r) if r.is_a?(Hash) }
        rows = fallback if rows.empty?

        rows.each { |r| fill_amounts(r) }
        rows.reject! { |r| r["amount"].nil? }
        balance_rounding(rows, warnings)
        rows.each_with_index do |r, i|
          days = r.delete("days")
          months = r.delete("months")
          r["due_on"] = (@issue_date + days).iso8601 if @issue_date && days
          r["due_on"] = (@issue_date >> months).iso8601 if @issue_date && months
          r["position"] = i
        end

        warnings << "Payment dates could not be worked out from the terms; fill them in if needed." if rows.any? && rows.none? { |r| r["due_on"] }
        { "installments" => rows, "warnings" => warnings }
      end

      private

      def normalize(row)
        description = row["description"].to_s.gsub(/\s+/, " ").strip
        percent = Numbers.percent(row["percent"])
        amount = Numbers.money(row["amount"])
        return nil if percent.nil? && amount.nil? && description.blank?

        {
          "description" => description.presence || "Payment",
          "percent" => percent,
          "amount" => amount&.positive? ? amount : nil,
          "days" => row["days_after_po"].to_s[/\d+/]&.to_i
        }
      end

      def fill_amounts(row)
        if row["amount"].nil? && row["percent"] && @total.positive?
          row["amount"] = (@total * row["percent"] / 100).round(2)
        elsif row["amount"] && row["percent"].nil? && @total.positive?
          row["percent"] = (row["amount"] / @total * 100).round(3)
        end
      end

      # Percentages that add up to 100 must add up to the PO total to the cent.
      def balance_rounding(rows, warnings)
        return if rows.empty? || !@total.positive?

        percent_sum = rows.sum { |r| r["percent"].to_f }
        amount_sum = rows.sum { |r| r["amount"].to_f }.round(2)
        if (percent_sum - 100).abs < 0.01 && (amount_sum - @total).abs < 1
          rows.last["amount"] = (rows.last["amount"] + (@total - amount_sum)).round(2)
        elsif (amount_sum - @total).abs > 0.05
          warnings << "The payment schedule adds up to #{format('%.2f', amount_sum)} but the PO total is #{format('%.2f', @total)}. Check the schedule."
        end
      end

      # Used when the model returned no installments but the terms are simple.
      def fallback
        text = @terms.gsub(/\s+/, " ").strip
        return [] if text.blank?

        if (m = text.match(/(\d+)\s*days?/i)) && !text.match?(/\d+\s*%/)
          [{ "description" => text, "percent" => 100.0, "amount" => nil, "days" => m[1].to_i }]
        elsif (m = text.match(/(annual|yearly)\D{0,40}(\d+)\s*years?/i)) && (amt = text[/\(\s*[A-Z]{3}\s*([\d.,]+)\s*\)/, 1])
          count = m[2].to_i.clamp(1, 20)
          (0...count).map do |i|
            { "description" => "Annual payment #{i + 1} of #{count}", "percent" => nil, "amount" => Numbers.money(amt), "months" => 12 * i }
          end
        else
          []
        end
      end
    end
  end
end
