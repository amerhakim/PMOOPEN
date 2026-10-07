require "roo"
require "tmpdir"

module VendorManagement
  module PoReader
    # Reads spreadsheets that look different from person to person -- one PO
    # per sheet, or many POs in one table. Columns are recognised by their
    # titles (a wide synonym table, in code, so it is fast and predictable); the
    # local AI is asked only about what the titles did not settle, and it
    # answers with a header TEXT (which code maps back to a column) rather than
    # a position, because a small model counts columns badly. Rows are then
    # processed by plain code, so big files stay fast.
    class ExcelReader
      FIELDS = %w[po_number issue_date supplier currency quotation_ref section part_no description
                  quantity unit_price line_total po_total payment_terms].freeze

      SYNONYMS = {
        "po_number" => ["po number", "po no", "po no.", "po #", "po", "purchase order", "purchase order no", "purchase order number", "po ref",
                        "order no", "order number", "order #", "ref", "reference", "po reference"],
        "issue_date" => ["po date", "date", "issue date", "order date", "date issued"],
        "supplier" => ["supplier", "vendor", "supplier name", "vendor name", "supplier/vendor"],
        "currency" => ["currency", "curr", "cur", "ccy"],
        "quotation_ref" => ["quotation", "quote ref", "quotation ref", "quote no", "quotation reference", "quotation no"],
        "section" => ["section", "group", "category", "lot"],
        "part_no" => ["part no", "part number", "part #", "part", "sku", "item code", "code", "pn", "part no.", "product code"],
        "description" => ["description", "item", "item description", "details", "particulars", "product", "service", "items", "scope"],
        "quantity" => ["qty", "quantity", "units", "no of units", "qty."],
        "unit_price" => ["unit price", "price", "rate", "unit cost", "unit rate", "price per unit"],
        "line_total" => ["total price", "line total", "amount", "total", "value", "extended price", "net amount", "line amount", "total amount"],
        "po_total" => ["po total", "po value", "po amount", "order total", "order value"],
        "payment_terms" => ["payment terms", "payment term", "terms of payment", "payment", "terms"]
      }.freeze

      META_LABELS = {
        "supplier" => /\A(vendor|supplier)(\s+name)?\s*:?\z/i,
        "po_number" => /\A(po|purchase\s+order|order)(\s*(no\.?|number|#|ref))?\s*:?\z/i,
        "currency" => /\Acurrency\s*:?\z/i,
        "issue_date" => /\A(po\s+)?date\s*:?\z/i,
        "payment_terms" => /\Apayment\s+terms?\s*:?\z/i
      }.freeze

      HEADER_ROW_PROMPT = <<~PROMPT.freeze
        Below are the first rows of one sheet of a spreadsheet that lists purchase orders (POs) or their items.
        Which row number (as printed) holds the column titles of the table? Answer ONLY with JSON: {"header_row": <number, 0 if none>}
        ROWS:
        %<rows>s
      PROMPT

      COLUMN_PROMPT = <<~PROMPT.freeze
        A spreadsheet table of purchase order items has these column titles: %<headers>s
        First data row: %<sample>s
        For each field below answer the EXACT column title (copied from the list) that holds it, or null if no column does.
        Answer ONLY with JSON: {%<fields>s}
        Field meanings: description = what is bought; quantity = how many; unit_price = price of one; line_total = price of the row (quantity x unit price);
        po_number = purchase order number/reference; supplier = vendor name; currency; issue_date = PO date; part_no = part/item code; payment_terms.
      PROMPT

      def initialize(bytes, filename, client: OllamaClient.new)
        @bytes = bytes
        @filename = filename
        @client = client
      end

      # => { "pos" => [...], "warnings" => [...], "mapping" => [{sheet, header_row, columns, meta}] }
      def call
        warnings = []
        mappings = []
        pos = []

        with_workbook do |book|
          book.sheets.each do |name|
            rows = read_rows(book.sheet(name))
            next if rows.size < 2

            mapping = map_sheet(rows, warnings, name)
            mappings << mapping.merge("sheet" => name)
            next if mapping["columns"].values.compact.empty?

            pos.concat(build_pos(rows, mapping, name, warnings))
          end
        end

        warnings << "No purchase orders could be found in this file." if pos.empty?
        { "pos" => pos, "warnings" => warnings.uniq, "mapping" => mappings }
      end

      private

      def with_workbook
        Dir.mktmpdir("po_intake_xl") do |dir|
          ext = File.extname(@filename).downcase.delete(".")
          path = File.join(dir, "in.#{ext}")
          File.binwrite(path, @bytes)
          yield Roo::Spreadsheet.open(path, extension: ext.to_sym)
        end
      end

      def read_rows(sheet)
        return [] if sheet.last_row.nil?

        (1..sheet.last_row).map { |r| sheet.row(r).map { |c| c.is_a?(String) ? c.gsub(/\s+/, " ").strip : c } }
      end

      # ---- column mapping -------------------------------------------------

      def map_sheet(rows, warnings, sheet_name)
        header_row = guess_header_row(rows)
        header_row = ai_header_row(rows, warnings, sheet_name) if header_row.zero?
        titles = header_row.positive? ? rows[header_row - 1].map { |c| c.to_s.strip } : []

        columns = {}
        used = []
        FIELDS.each do |field|
          idx = synonym_column(titles.map(&:downcase), field, used)
          columns[field] = idx
          used << idx if idx
        end
        ai_fill_columns(titles, rows[header_row], columns, used, warnings, sheet_name) if header_row.positive? && needs_ai?(columns)

        { "header_row" => header_row, "columns" => columns, "meta" => meta_from_rows(rows.first([header_row - 1, 0].max)) }
      end

      def needs_ai?(columns)
        columns["description"].nil? || (columns["line_total"].nil? && columns["unit_price"].nil?)
      end

      # The header row is the one whose cells most often look like a known
      # column title ("Qty", "Order Ref", "Unit Price" ...).
      def guess_header_row(rows)
        words = SYNONYMS.values.flatten.uniq
        scores = rows.first(30).each_with_index.map do |row, i|
          hits = row.count do |cell|
            next false unless cell.is_a?(String) && cell.length <= 40

            text = cell.downcase.strip
            words.include?(text) || words.any? { |w| w.length > 2 && text.match?(/\b#{Regexp.escape(w)}\b/) }
          end
          [i + 1, hits]
        end
        best = scores.max_by { |row_number, hits| [hits, -row_number] }
        best && best[1] >= 2 ? best[0] : 0
      end

      def synonym_column(titles, field, used)
        SYNONYMS[field].each do |word|
          idx = titles.each_index.find { |i| titles[i] == word && !used.include?(i) }
          return idx if idx
        end
        SYNONYMS[field].each do |word|
          idx = titles.each_index.find { |i| !used.include?(i) && titles[i].length <= 40 && titles[i].match?(/\b#{Regexp.escape(word)}\b/) }
          return idx if idx
        end
        nil
      end

      def ai_header_row(rows, warnings, sheet_name)
        listing = rows.first(15).each_with_index.filter_map do |row, i|
          cells = row.each_with_index.filter_map { |c, ci| "[#{ci}] #{c}" unless c.nil? || c.to_s.strip.empty? }
          "row #{i + 1}: #{cells.join(' | ')}" if cells.any?
        end.join("\n")
        answer = @client.generate_json(HEADER_ROW_PROMPT.sub("%<rows>s") { listing.truncate(3000) }, max_tokens: 40)
        answer.is_a?(Hash) ? answer["header_row"].to_i : 0
      rescue OllamaClient::Error => e
        warnings << "Sheet \"#{sheet_name}\": could not find the column titles (#{e.message})."
        0
      end

      # Asks only about the fields the titles did not settle; the answer is a
      # header text, mapped back to its column here.
      def ai_fill_columns(titles, sample_row, columns, used, warnings, sheet_name)
        missing = FIELDS.select { |f| columns[f].nil? && %w[description quantity unit_price line_total po_number supplier currency issue_date part_no payment_terms].include?(f) }
        return if missing.empty?

        prompt = COLUMN_PROMPT.sub("%<headers>s") { titles.reject(&:blank?).join(" | ") }
                              .sub("%<sample>s") { Array(sample_row).map(&:to_s).join(" | ").truncate(300) }
                              .sub("%<fields>s") { missing.map { |f| "\"#{f}\": null" }.join(", ") }
        answer = @client.generate_json(prompt, max_tokens: 200)
        return unless answer.is_a?(Hash)

        missing.each do |field|
          wanted = answer[field].to_s.strip.downcase
          next if wanted.empty?

          idx = titles.each_index.find { |i| titles[i].downcase == wanted && !used.include?(i) }
          next unless idx

          columns[field] = idx
          used << idx
        end
      rescue OllamaClient::Error => e
        warnings << "Sheet \"#{sheet_name}\": the AI was not available (#{e.message}); columns were matched by their titles only."
      end

      # "Supplier: ACME" / "PO No | S-77" style cells above the table.
      def meta_from_rows(rows)
        meta = {}
        rows.each do |row|
          row.each_with_index do |cell, i|
            next unless cell.is_a?(String)

            META_LABELS.each do |field, regex|
              next if meta[field] || !cell.strip.match?(regex)

              value = row[(i + 1)..].to_a.find { |c| !c.nil? && c.to_s.strip != "" }
              meta[field] = value.respond_to?(:to_date) && !value.is_a?(String) ? value.to_date.iso8601 : value.to_s.strip if value
            end
          end
        end
        meta
      end

      # ---- rows -> POs ----------------------------------------------------

      def build_pos(rows, mapping, sheet_name, warnings)
        cols = mapping["columns"]
        meta = mapping["meta"]
        start = mapping["header_row"]
        data = rows[start..] || []
        pos = {}
        order = []
        current = nil
        section = nil

        data.each_with_index do |row, i|
          next if row.compact.all? { |c| c.to_s.strip.empty? }

          get = ->(field) { cols[field] ? row[cols[field]] : nil }
          description = get.call("description").to_s.strip
          quantity = Numbers.parse(get.call("quantity"))
          unit = Numbers.money(get.call("unit_price"))
          total = Numbers.money(get.call("line_total"))
          po_number = get.call("po_number").to_s.strip.presence

          if po_number.nil? && description.present? && quantity.nil? && unit.nil? && total.nil? && current.nil?
            section = description
            next
          end
          next if description.blank? && quantity.nil? && unit.nil? && total.nil?
          next if description.match?(/\A(sub\s*)?total\b/i) && quantity.nil?

          key = po_number || current || meta["po_number"].presence || sheet_name
          current = key
          unless pos[key]
            pos[key] = new_po(key, meta, sheet_name)
            order << key
            section = nil
          end
          po = pos[key]
          fill_header(po, row, cols)
          po["lines"] << {
            "section" => (get.call("section").to_s.strip.presence || section),
            "part_no" => get.call("part_no").to_s.strip.presence,
            "description" => description.presence || "Item #{po['lines'].size + 1}",
            "quantity" => quantity, "unit_price" => unit, "line_total" => total
          }
          warnings << "Sheet \"#{sheet_name}\": row #{start + i + 1} has no amounts." if quantity.nil? && unit.nil? && total.nil?
        end
        order.map { |k| pos[k] }
      end

      def new_po(key, meta, sheet_name)
        {
          "po_number" => key == sheet_name ? meta["po_number"] : key,
          "issue_date_text" => meta["issue_date"], "supplier_name" => meta["supplier"],
          "quotation_ref" => nil, "currency" => meta["currency"], "total_value" => nil,
          "order_description" => nil, "special_note" => nil, "payment_terms" => meta["payment_terms"],
          "incoterm" => nil, "delivery_address" => nil, "end_user_name" => nil,
          "installments" => [], "lines" => [], "warnings" => [], "source_sheet" => sheet_name
        }
      end

      def fill_header(po, row, cols)
        { "issue_date_text" => "issue_date", "supplier_name" => "supplier", "currency" => "currency",
          "quotation_ref" => "quotation_ref", "payment_terms" => "payment_terms" }.each do |key, field|
          value = cols[field] ? row[cols[field]] : nil
          value = value.to_date.iso8601 if value.respond_to?(:to_date) && !value.is_a?(String) && key == "issue_date_text"
          po[key] ||= value.to_s.strip.presence if value
        end
        total = cols["po_total"] ? Numbers.money(row[cols["po_total"]]) : nil
        po["total_value"] ||= total
      end
    end
  end
end
