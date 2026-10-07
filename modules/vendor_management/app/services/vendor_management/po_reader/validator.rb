module VendorManagement
  module PoReader
    # Arithmetic safety net over what the AI/OCR read: quantity x unit price
    # must equal the line total, and the lines must add up to the PO total.
    # Wrong digits are repaired when exactly one repair makes the numbers
    # agree; everything else is flagged for the reviewer, never hidden.
    class Validator
      TOLERANCE = 0.02

      # ocr_numbers: every amount printed on the scan (Set of Float), when the
      # PO came from an image. Lets a wrong digit be caught or repaired by
      # comparing with what is really printed.
      def initialize(po, ocr_numbers: nil)
        @po = po
        @ocr = ocr_numbers
      end

      def call
        warnings = Array(@po["warnings"])
        @po["lines"].each do |line|
          check_line(line)
          cross_check(line)
        end

        # the PO total is the lines less the discount (the discount is its own field)
        sum = (@po["lines"].sum { |l| l["line_total"].to_f } - @po["discount"].to_f).round(2)
        total = @po["total_value"]
        if @po["lines"].any?
          if total.nil?
            @po["total_value"] = sum
            warnings << "The PO total was not found; using the sum of the lines (#{amount(sum)})."
          elsif (sum - total).abs > TOLERANCE
            warnings << "The lines add up to #{amount(sum)} but the PO total is #{amount(total)} " \
                        "(difference #{amount(sum - total)}). Check the highlighted lines."
            missing_row_hint(total - sum, warnings)
          end
        elsif total.nil?
          warnings << "No items and no total were found."
        end

        normalize_currency(warnings)
        @po["warnings"] = warnings.uniq
        @po
      end

      private

      def normalize_currency(warnings)
        currency = @po["currency"].to_s.upcase.presence
        if currency.nil?
          warnings << "No currency was found; set to QAR."
          currency = "QAR"
        elsif !VendorManagement::PurchaseOrder::CURRENCIES.include?(currency)
          warnings << "Currency #{currency} is not supported here; set to QAR."
          currency = "QAR"
        end
        @po["currency"] = currency
      end

      # Compare a line with the amounts really printed on the scan.
      def cross_check(line)
        return unless @ocr && line["line_total"]

        u = line["unit_price"].to_f
        t = line["line_total"].to_f
        return if t.zero? && u.zero?
        return if printed?(t)

        if u.positive? && printed?(u) && (k = (2..60).find { |n| printed?((u * n).round(2)) })
          line["flags"] << "The total #{amount(t)} is not on the scan; changed to #{amount(u * k)} (quantity #{k}) which is."
          line["quantity"] = k
          line["line_total"] = (u * k).round(2)
        else
          line["flags"] << "The amount #{amount(t)} was not found on the scan. Check it."
        end
      end

      def printed?(number)
        @ocr.include?(number.abs.round(2)) # the scan prints a discount without its minus sign too
      end

      # A positive gap that equals a printed amount usually means a row was missed.
      def missing_row_hint(gap, warnings)
        return unless @ocr && gap.positive? && printed?(gap)

        warnings << "The missing #{amount(gap)} is printed on the scan, so a row worth that amount was probably skipped. Add it."
      end

      def check_line(line)
        flags = []
        q = line["quantity"]
        u = line["unit_price"]
        t = line["line_total"]

        if q && u && t
          unless close?(q * u, t)
            if u.positive? && (k = lost_leading_digit(u, t))
              flags << "The total #{amount(t)} looks like #{amount(u * k)} with a lost digit; quantity set to #{k} so that quantity x unit price = total."
              q = k
              t = (u * k).round(2)
            elsif u.positive? && integral?(t / u)
              flags << "Quantity read as #{trim(q)}; changed to #{trim(t / u)} so that quantity x unit price = total."
              q = (t / u).round
            elsif q.positive? && ((t / q * 100) - (t / q * 100).round).abs < 1e-6
              flags << "Unit price read as #{amount(u)}; changed to #{amount(t / q)} so that quantity x unit price = total."
              u = (t / q).round(2)
            else
              flags << "Quantity x unit price (#{amount(q * u)}) does not match the total (#{amount(t)})."
            end
          end
        elsif t && u && q.nil?
          q = u.positive? && integral?(t / u) ? (t / u).round : 1
          flags << "Quantity was not readable; set to #{trim(q)}."
        elsif t && q && u.nil?
          u = q.positive? ? (t / q).round(2) : t
          flags << "Unit price was not readable; calculated from the total."
        elsif q && u && t.nil?
          t = (q * u).round(2)
        elsif t && q.nil? && u.nil?
          q = 1
          u = t
        elsif q.nil? && u.nil? && t.nil?
          q = 1
          u = 0.0
          t = 0.0
          flags << "No quantity or price was read for this line."
        else
          flags << "No price was read for this line." if u.nil? && t.nil?
          q ||= 1
          u ||= 0.0
          t ||= (q * u).round(2)
        end

        line["quantity"] = q
        line["unit_price"] = u
        line["line_total"] = t
        line["flags"] = flags
      end

      # OCR sometimes drops the first digit of an amount ("2,835.00" -> "835.00"):
      # the quantity whose product ends with the amount that was read.
      def lost_leading_digit(unit, total)
        read = format("%.2f", total)
        (2..60).find do |n|
          product = format("%.2f", unit * n)
          product.length > read.length && product.end_with?(read)
        end
      end

      def close?(a, b)
        (a - b).abs <= [TOLERANCE, b.abs * 0.0001].max
      end

      def integral?(n)
        n.positive? && (n - n.round).abs < 1e-6 && n.round < 100_000
      end

      def trim(n)
        n == n.round ? n.round.to_s : n.to_s
      end

      def amount(n)
        whole, decimals = format("%.2f", n.abs).split(".")
        sign = n.negative? ? "-" : ""
        "#{sign}#{whole.reverse.scan(/\d{1,3}/).join(',').reverse}.#{decimals}"
      end
    end
  end
end
