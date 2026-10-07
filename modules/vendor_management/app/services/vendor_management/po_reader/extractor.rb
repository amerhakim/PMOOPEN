module VendorManagement
  module PoReader
    # OCR text of one QDS purchase order -> a structured PO hash. A CPU-only
    # 7B model is slow per token, so the work is split and kept small:
    #   - printed anchors ("Purchase Order No.", "Total Amount in USD ...")
    #     are read by HeaderHeuristics, no model needed;
    #   - call 1 reads only the non-table text and answers just the fields
    #     the anchors did not give (plus the payment schedule);
    #   - call 2 reads only the items table and answers compact rows.
    class Extractor
      HEADER_PROMPT = <<~PROMPT.freeze
        You read OCR text of a Purchase Order that Qatar Datamation Systems (QDS) issued to a supplier. The OCR is noisy.
        Answer ONLY with JSON containing exactly these keys (null when not printed): %<keys>s
        Rules:
        - Copy text as printed; never invent anything.
        - order_description: a short title (max 100 characters) of what is being bought.
        - installments: how the SUPPLIER is paid, from "Payment Terms". One entry per payment:
          {"description": "", "percent": null, "amount": null, "days_after_po": null}. Use percent for percentages ("10% On Signing" -> 10),
          amount for amounts, days_after_po for "N days". "60 Days Credit" -> one entry percent 100, days_after_po 60.
          "Annual Payment for 3 Years (QAR 1,084,599.41)" -> 3 entries with that amount each. No payment information -> [].
        TEXT:
        %<text>s
      PROMPT

      LINES_PROMPT = <<~PROMPT.freeze
        You read the OCR text of the items table of a Purchase Order. Cells are separated by " | ".
        Answer ONLY with JSON: {"rows": [["section", "part_no", "description", qty, unit_price, total], ...]}
        Rules:
        - One row per table row, in order, including rows under headings such as "Optional: ..." or "Shipping & Cargo Charges"
          (a heading is the section for the rows below it; use "" when there is none). Never skip a row.
        - Join a description (and a part number) that wraps onto several lines into one value.
        - Numbers are plain numbers without thousands separators. A row with "-" or no price has unit_price 0 and total 0.
        - If there is no items table but a service with a price is described (for example a proposal cost with discounts), return ONE row:
          description = the service title, qty 1, unit_price and total = the FINAL price to be paid.
        - Do not add totals, taxes or payment-term rows.
        TEXT:
        %<text>s
      PROMPT

      HEADER_KEYS = {
        "order_description" => '""', "special_note" => '""', "incoterm" => '""', "delivery_address" => '""',
        "end_user_name" => '""', "installments" => "[...]",
        "po_number" => '""', "issue_date_text" => '"as printed, e.g. 10-Sep-26"', "supplier_name" => '""',
        "quotation_ref" => '""', "currency" => '"QAR|USD|SAR|OMR"', "total_value" => "0", "payment_terms" => '"verbatim"'
      }.freeze
      ANCHORED = %w[po_number issue_date_text supplier_name quotation_ref currency total_value payment_terms].freeze

      TABLE_START = /part\s*no|description|s\.?\s*no\b.*\bqty|unit\s*price/i
      TABLE_END = /total\s+amount\s+in|amount\s+in\s+words|final\s+discounted|payment\s+terms/i
      MAX_TEXT = 6000

      def initialize(text, client: OllamaClient.new, parsed_lines: [])
        @text = text.to_s
        @client = client
        @parsed_lines = Array(parsed_lines)
      end

      def call
        warnings = []
        anchors = HeaderHeuristics.new(@text).call
        # not the QDS template (supplier portals, distributor quotes): look for the labels such documents use
        @generic = anchors["po_number"].blank?
        anchors = anchors.merge(GenericHeader.new(@text).call) if @generic # the labels found win over the template guesses
        table_text, other_text = split_table(compact(@text))

        header = header_from_model(anchors, other_text, warnings)
        lines = choose_lines(anchors["total_value"], table_text, warnings)

        {
          "po_number" => anchors["po_number"] || header["po_number"],
          "issue_date_text" => anchors["issue_date_text"] || header["issue_date_text"],
          "supplier_name" => anchors["supplier_name"] || header["supplier_name"],
          "quotation_ref" => anchors["quotation_ref"] || header["quotation_ref"],
          "currency" => anchors["currency"] || header["currency"],
          "total_value" => anchors["total_value"] || Numbers.money(header["total_value"]),
          "order_description" => anchors["order_description"].presence || header["order_description"].presence || describe(lines),
          "special_note" => anchors["special_note"] || header["special_note"],
          "payment_terms" => anchors["payment_terms"] || header["payment_terms"],
          "incoterm" => anchors["incoterm"] || header["incoterm"],
          "delivery_address" => header["delivery_address"],
          "end_user_name" => anchors["end_user_name"] || header["end_user_name"],
          "installments" => Array(anchors["installments"] || header["installments"]),
          "lines" => lines,
          "discount" => @discount.to_f.positive? ? @discount : nil,
          "warnings" => warnings
        }
      end

      private

      # Collapse the layout whitespace (it costs a lot of model tokens) into
      # " | " cell separators and drop empty lines and OCR debris.
      def compact(text)
        text.lines.filter_map do |line|
          cleaned = line.strip.gsub(/\s{2,}/, " | ").gsub(/(\| )+\|/, "|")
          next if cleaned.empty? || cleaned.length < 3 || cleaned.match?(/\A[\W_]+\z/)

          cleaned
        end
      end

      # => [table_text, everything_else_text]
      def split_table(lines)
        start = lines.index { |l| l.match?(TABLE_START) && l.count("|") >= 2 } || lines.index { |l| l.match?(TABLE_START) }
        return [lines.join("\n").truncate(MAX_TEXT), lines.join("\n").truncate(MAX_TEXT)] if start.nil?

        stop = lines[start..].index { |l| l.match?(TABLE_END) }
        stop = stop ? start + stop : lines.size - 1
        table = lines[start..stop]
        other = lines[0...start] + lines[(stop + 1)..].to_a
        [table.join("\n").truncate(MAX_TEXT), other.join("\n").truncate(MAX_TEXT)]
      end

      # The model is only asked for what the printed anchors did not give.
      # Simple payment terms ("60 Days Credit", "Annual payment for 3 years
      # (QAR ...)", percentages) are turned into a schedule by PaymentSchedule
      # without it.
      def header_from_model(anchors, other_text, warnings)
        # a document that is not on the QDS template rarely prints all of these; the reviewer fills the rest in
        # (waiting minutes for a slow model to guess them is not worth it)
        wanted = @generic ? %w[po_number] : %w[po_number issue_date_text supplier_name total_value currency]
        critical = wanted.reject { |k| anchors[k] }
        terms = anchors["payment_terms"].to_s
        simple_terms = anchors["installments"] || terms.match?(/\d+\s*days?/i) || terms.match?(/(annual|yearly)\D{0,40}\d+\s*years?/i) || terms.blank?
        return {} if critical.empty? && simple_terms

        needed = %w[order_description delivery_address] + critical + (simple_terms ? [] : %w[installments])
        needed += %w[quotation_ref payment_terms special_note incoterm end_user_name].reject { |k| anchors[k] }
        keys = "{#{needed.uniq.map { |k| "\"#{k}\": #{HEADER_KEYS[k]}" }.join(', ')}}"
        ask(HEADER_PROMPT, { keys:, text: other_text }, 700, warnings, "header")
      end

      # The table read from the scan's geometry is exact when it adds up to the
      # printed total; otherwise the model reads the items (and the closer of
      # the two wins).
      # Purchase orders here cannot hold a negative line, so a discount line printed in the
      # document is left out and reported (the lines were matched against the total with it in).
      def choose_lines(total, table_text, warnings)
        lines = choose_lines_with_discounts(total, table_text, warnings)
        discounts, kept = lines.partition { |l| l["line_total"].to_f.negative? || l["unit_price"].to_f.negative? }
        @discount = discounts.sum { |d| d["line_total"].to_f.abs }.round(2)
        warnings << "The document has a discount of #{format('%.2f', @discount)}; it is entered in the Discount field, so the PO total matches the document." if @discount.positive?
        kept
      end

      def choose_lines_with_discounts(total, table_text, warnings)
        parsed_sum = @parsed_lines.sum { |l| l["line_total"].to_f }
        narrative = narrative_line(total, warnings)
        return narrative if narrative
        if @parsed_lines.any? && (total.nil? || (parsed_sum - total).abs <= [total * 0.005, 1.0].max)
          return @parsed_lines
        end
        # Quantities but no prices (a quote that only prints the grand total): keep the items,
        # and put the printed total on one extra line so the PO value is right.
        if @parsed_lines.size >= 2 && total && parsed_sum.zero?
          warnings << "The document shows quantities but no price per item; the items were entered with no price and one line carries the total."
          items = @parsed_lines.map { |l| l.merge("unit_price" => 0.0, "line_total" => 0.0) }
          return items + [{ "section" => nil, "part_no" => nil, "description" => "Total price of the items above (as printed in the document)",
                            "quantity" => 1, "unit_price" => total, "line_total" => total }]
        end
        # A few misread digits are repaired by the Validator (and flagged); only a table
        # that is far off is worth the minutes the model needs to read it again.
        if @parsed_lines.size >= 3 && total && (parsed_sum - total).abs <= total * 0.1
          warnings << "The table was read from the scan; a few amounts were misread and were corrected or flagged below."
          return @parsed_lines
        end

        rows = ask(LINES_PROMPT, { text: table_text }, 2500, warnings, "items")
        from_model = dedupe(rows_to_lines(rows))
        return from_model.presence || fallback_line(total, warnings) if @parsed_lines.empty?
        return fallback_line(total, warnings) if from_model.empty?

        model_sum = from_model.sum { |l| l["line_total"].to_f }
        if (model_sum - total.to_f).abs < (parsed_sum - total.to_f).abs
          warnings << "The table read from the scan did not add up to the PO total, so the AI's reading of the items was used."
          from_model
        else
          @parsed_lines
        end
      end

      # Service POs describe a price build-up (proposal cost, discounts, "Final
      # Discounted Price") instead of items. That is one line at the final price.
      def narrative_line(total, warnings)
        return nil unless total && @parsed_lines.size >= 2

        buildup = @parsed_lines.count { |l| l["description"].to_s.match?(/discount|revised|reduced|original|proposal/i) }
        return nil unless buildup >= 2

        title = @parsed_lines.first["section"].presence || "Services per the purchase order"
        steps = @parsed_lines.filter_map { |l| l["description"].presence }.join("; ")
        warnings << "The PO shows a price build-up (#{steps}); it was entered as one line at the final price."
        [{ "section" => nil, "part_no" => nil, "description" => title, "quantity" => 1, "unit_price" => total, "line_total" => total }]
      end

      # Nothing readable but the printed total: keep the PO's value with one
      # line the reviewer can rename or split.
      def fallback_line(total, warnings)
        return [] unless total

        warnings << "The items could not be read; one line was created for the PO total. Replace it with the real items."
        [{ "section" => nil, "part_no" => nil, "description" => @parsed_lines.first&.dig("section").presence || "As per the purchase order",
           "quantity" => 1, "unit_price" => total, "line_total" => total }]
      end

      def describe(lines)
        first = lines.first
        return nil unless first

        (first["section"].presence || first["description"]).to_s.truncate(100)
      end

      # The model sometimes repeats rows (once without and once with their
      # section heading). Same part number + prices (or same description +
      # total) = same row; keep the one that has a section.
      def dedupe(lines)
        kept = {}
        lines.each do |l|
          key = [l["part_no"].to_s.downcase.presence || l["description"].to_s.downcase.first(30), l["unit_price"], l["line_total"]]
          if kept[key]
            kept[key] = l if kept[key]["section"].blank? && l["section"].present?
          else
            kept[key] = l
          end
        end
        kept.values
      end

      def ask(template, values, max_tokens, warnings, label)
        prompt = values.reduce(template) { |acc, (key, value)| acc.sub("%<#{key}>s") { value.to_s } }
        answer = @client.generate_json(prompt, max_tokens:)
        answer.is_a?(Hash) ? answer : {}
      rescue OllamaClient::Error => e
        warnings << "AI could not read the #{label}: #{e.message}"
        {}
      end

      def rows_to_lines(answer)
        Array(answer["rows"]).filter_map do |row|
          row = row.values if row.is_a?(Hash)
          next unless row.is_a?(Array) && row.size >= 3

          section, part_no, description, qty, unit, total = row.size >= 6 ? row[0, 6] : ["", nil, *row[0, 4]]
          {
            "section" => section.to_s.strip.presence,
            "part_no" => part_no.to_s.strip.presence,
            "description" => description.to_s.gsub(/\s+/, " ").strip,
            "quantity" => Numbers.parse(qty),
            "unit_price" => Numbers.money(unit),
            "line_total" => Numbers.money(total)
          }
        end.reject { |l| l["description"].blank? && l["line_total"].nil? }
      end
    end
  end
end
