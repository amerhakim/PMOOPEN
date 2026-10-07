module VendorManagement
  module PoReader
    # Finds the header facts of a PO or quotation that is NOT on the QDS
    # template (supplier portals, distributor quotes, ...) by looking for the
    # labels such documents use ("Quote Number:", "Issued By:", "Currency:",
    # "Total Price : ..."), in the PDF's text or the OCR text, whatever the
    # layout. Plain code, so it takes milliseconds.
    class GenericHeader
      DATE = %r{\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}[\- /][A-Za-z]{3,9}[\- /,]+\d{2,4}|[A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}}
      ID = %r{[A-Za-z0-9][A-Za-z0-9\-/_.]{2,}}
      CURRENCIES = %w[QAR USD SAR OMR].freeze

      NUMBER_LABELS = [
        /purchase\s*order\s*(?:no\.?|number|#)?/i,
        /\bPO\s*(?:no\.?|number|#)/i,
        /order\s*(?:no\.?|number|#)/i,
        /quot(?:e|ation)(?:\s*(?:no\.?|number|#))?/i,
        /deal\s*id\s*#?/i
      ].freeze
      DATE_LABELS = /(?:quote\s*created\s*date|quote\s*distribution\s*date|issue\s*date|order\s*date|quote\s*date|created\s*date|date\s*of\s*issue|date)/i
      VENDOR_LABELS = /\A(?:issued\s*by|supplier(?:\s*name)?|vendor(?:\s*name)?|seller|sold\s*by)\s*:?\z/i
      CUSTOMER_LABELS = /\A(?:customer(?:\s*name)?|end\s*user|end\s*customer|client)\s*:?\z/i
      TOTAL = /(?:grand\s*total|net\s*total|total\s*(?:price|amount|value)|total)\s*(?:in\s+[A-Z]{3})?\s*[:\-]?\s*(?:[A-Z]{3}\s*)?(\d[\d,]*\.\d{2})/i

      def initialize(text)
        @text = text.to_s.tr("\f", "\n")
        @lines = @text.lines.map(&:chomp)
      end

      def call
        {
          "po_number" => po_number,
          "issue_date_text" => issue_date,
          "currency" => currency,
          "supplier_name" => labelled_value(VENDOR_LABELS) || company_at_top,
          "end_user_name" => customer,
          "total_value" => total,
          "payment_terms" => payment_terms,
          "order_description" => order_description
        }.compact.reject { |_k, v| v.respond_to?(:empty?) && v.empty? }
      end

      private

      def po_number
        NUMBER_LABELS.each do |label|
          m = @text.match(/#{label.source}\s*[:#]\s*#?\s*(#{ID.source})/i)
          return m[1] if m && m[1].match?(/\d/)
        end
        nil
      end

      def issue_date
        @text[/#{DATE_LABELS.source}\s*[:]\s*(#{DATE.source})/i, 1]
      end

      def currency
        explicit = @text[/currency\s*[:]?\s*(#{CURRENCIES.join('|')})\b/i, 1]
        return explicit.upcase if explicit

        counts = CURRENCIES.to_h { |c| [c, @text.scan(/\b#{c}\b/).size] }
        best = counts.max_by { |_c, n| n }
        return best.first if best.last.positive?

        "USD" if @text.match?(/List\s*Prc(?:USD|UD)\b/i)
      end

      # "Label:   value" on one line (two-column pages put several pairs on a line),
      # or the label alone with its value on the next line.
      def labelled_value(label_regex)
        @lines.each_with_index do |line, i|
          cells = cells_of(line)
          cells.each_with_index do |(cell, start), j|
            inline = cell.match(/\A(.+?):\s+(\S.*)\z/)
            if inline && inline[1].match?(label_regex)
              return clean(inline[2])
            elsif cell.match?(label_regex)
              value = cells[j + 1]&.first || next_line_value(i, start)
              return clean(value) if value.present? && !value.match?(/\A[\w\s]{1,20}:\z/)
            end
          end
        end
        nil
      end

      def cells_of(line)
        line.to_enum(:scan, /\S+(?: \S+)*/).map { [Regexp.last_match[0], Regexp.last_match.begin(0)] }
      end

      COMPANY = /\b(?:LLC|L\.L\.C\.?|W\.L\.L\.?|Ltd\.?|Limited|Co\.?|Company|Trading|Inc\.?|FZE|FZ-?LLC|FZCO|Corporation|Corp\.?)(?:\s|\z)/i

      # Quotes usually print the issuing company in the top left corner, with no label.
      def company_at_top
        @lines.first(25).each do |line|
          first = cells_of(line).first
          next unless first && first[1] < 6 && first[0].match?(COMPANY)
          next if first[0].match?(/datamation|\bQDS\b/i)

          return clean(first[0])
        end
        nil
      end

      def customer
        value = labelled_value(CUSTOMER_LABELS)
        value&.sub(/\A\d{6,}\s+/, "")&.then { |v| v.presence }
      end

      # the value under a label: the first text on one of the next lines that sits near the label's column
      def next_line_value(index, label_start)
        (1..3).each do |k|
          cells_of(@lines[index + k].to_s).each do |text, start|
            return text if start >= label_start - 2 && start <= label_start + 40
          end
        end
        nil
      end

      def total
        found = @text.scan(TOTAL).flatten.map { |v| Numbers.money(v) }.compact
        found.max
      end

      def payment_terms
        @text[/payment\s*terms?\s*:\s*([^\n]+)/i, 1]&.then { |v| clean(v.split(/\s{3,}/).first) }
      end

      def order_description
        @text[/(?:deal\s*description|subject|project\s*name)\s*:\s*([^\n]+)/i, 1]&.then { |v| clean(v.split(/\s{3,}/).first)&.truncate(100) }
      end

      def clean(value)
        value.to_s.gsub(/[|\[\]_]+/, " ").gsub(/\s+/, " ").strip.presence
      end
    end
  end
end
