module VendorManagement
  module PoReader
    # QDS purchase orders share one template, so the printed anchors in the OCR
    # text ("Purchase Order No.", "Supplier Name:", "Total Amount in USD ...",
    # "Payment Terms: 10% On Signing ...") are read by plain code. That is
    # faster and more exact than a CPU-only model; the model only fills gaps.
    class HeaderHeuristics
      TOTAL_LABEL = /(?:Total\s+Amount|Final\s+Discounted\s+Price|Grand\s+Total)\s+in\s+([A-Z]{3})\s*[:\-]?\s*([\d.,]+)/i

      def initialize(text)
        @text = text.to_s
      end

      def call
        first_page = @text.split(/=== PAGE 2 ===/).first.to_s
        currency, total = @text.match(TOTAL_LABEL)&.captures
        terms_block = payment_terms_block
        {
          "po_number" => match(/Purchase\s+Order\s+No\.?[ \t]*:?[ \t]*([A-Z]{2,5}\/[A-Z0-9\-]+\/\d+)/i),
          "supplier_name" => clean_name(match(/Supplier\s+Name[ \t]*:?[ \t]*[^\w\n]*([^\n]+)/i)),
          "quotation_ref" => match(/Quotation\s+Reference\s+No\.?[ \t]*:?[ \t]*([A-Za-z0-9][^\n|]*)/i),
          "issue_date_text" => first_page[/\b\d{1,2}[-\/][A-Za-z]{3}[-\/]\d{2,4}\b/],
          "currency" => currency&.upcase,
          "total_value" => Numbers.money(total),
          "payment_terms" => flatten(terms_block),
          "special_note" => clean_name(match(/Special\s+Note[ \t]*:?[ \t]*([^\n]+)/i)),
          "incoterm" => match(/Inco\s*Terms\s*:?\s*([A-Z]{3})\b/),
          "end_user_name" => clean_name(match(/End\s+User\s+Company\s+Name\s*[|:]?\s*([^\n|]+?)(?:\s+Inco|\s*\||\n|\z)/i)),
          "installments" => percent_schedule(terms_block)
        }.compact.reject { |_k, v| v.respond_to?(:empty?) && v.empty? }
      end

      private

      def match(regex)
        @text[regex, 1]&.strip.presence
      end

      def clean_name(name)
        name&.gsub(/[|\[\]_]+/, " ")&.gsub(/\s+/, " ")&.strip.presence
      end

      def payment_terms_block
        @text[/Payment\s+Terms\s*:?(.*?)(?:\n\s*Delivery\s*:|\n\s*End[-\s]*User|\z)/mi, 1]
      end

      def flatten(block)
        block&.gsub(/[|\[\]]+/, " ")&.gsub(/\s+/, " ")&.strip.presence
      end

      # "Advance | 10% On Signing / Advance 10% 1-Month After / 15% On Completion ..."
      # -> one installment per percentage, described by the words around it.
      def percent_schedule(block)
        text = flatten(block)
        return nil if text.nil?

        parts = text.split(/(\d+(?:\.\d+)?)\s*%/)
        return nil if parts.size < 3

        rows = []
        prefix = parts[0].to_s.strip
        (1...parts.size).step(2) do |i|
          percent = parts[i].to_f
          words = parts[i + 1].to_s.strip
          # the label for the next percentage often starts at the end of these words ("... Completion 15% ...")
          next_label = words.sub!(/\s+(Advance|FD|Final|Balance|Retention)\z/i, "") ? Regexp.last_match(1) : nil
          rows << { "description" => [prefix, "#{percent.to_i == percent ? percent.to_i : percent}%", words].reject(&:blank?).join(" "),
                    "percent" => percent, "amount" => nil, "days_after_po" => nil }
          prefix = next_label.to_s
        end
        sum = rows.sum { |r| r["percent"] }
        (sum - 100).abs < 0.5 ? rows : nil
      end
    end
  end
end
