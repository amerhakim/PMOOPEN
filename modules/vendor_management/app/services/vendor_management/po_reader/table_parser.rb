module VendorManagement
  module PoReader
    # Reads the items table of a scanned PO from tesseract's word positions
    # (TSV), no language model needed. The table is drawn with ruled lines;
    # tesseract reports each ruled line as a very wide blank "word", which
    # gives the row boundaries. Inside a row, the money amounts on the right
    # are the unit price and total, a small whole number before them is the
    # quantity, and the text on the left is the part number and description
    # (wrapped over several lines, centred vertically in the cell -- which is
    # exactly why rows must be cut by the ruled lines and not by text lines).
    class TableParser
      MONEY = /\A\d[\d,.]*[.,]\d{2}\z/
      DASH = /\A[-–—]\z/
      SKU = /\A(?=.*\d)[A-Z0-9]{2,}(?:-[A-Z0-9]{1,}){1,}-?\z/i
      DATE = /\A\d{1,2}-\d{1,2}-\d{2,4}\z/
      Word = Struct.new(:block, :par, :line, :x, :y, :w, :h, :conf, :text) do
        def cy = y + (h / 2.0)
        def right = x + w
      end

      def initialize(tsv_pages)
        @pages = Array(tsv_pages)
      end

      # => array of line hashes ("section", "part_no", "description", "quantity", "unit_price", "line_total")
      def call
        @pages.flat_map { |tsv| parse_page(tsv) }
      rescue StandardError
        []
      end

      private

      def parse_page(tsv)
        words = tsv.lines.drop(1).filter_map do |l|
          f = l.chomp.split("\t", -1)
          next unless f[0] == "5" && f.size >= 12

          Word.new(f[2].to_i, f[3].to_i, f[4].to_i, f[6].to_i, f[7].to_i, f[8].to_i, f[9].to_i, f[10].to_f, f[11].to_s)
        end
        text_words = words.reject { |w| w.text.strip.empty? }
        header = header_words(text_words)
        return [] unless header

        width = header[:right] - header[:left]
        borders = words.select { |w| w.text.strip.empty? && w.w >= width * 0.5 && (w.x - header[:left]).abs < 150 && w.cy > header[:cy] + 15 }
                       .map(&:cy).sort
        stop_y = table_end(text_words, header)
        bounds = borders.select { |b| b < stop_y }
        return [] if bounds.size < 2

        rows = bounds.each_cons(2).filter_map do |top, bottom|
          row_words = text_words.select { |w| w.cy > top && w.cy < bottom }
          row_words.empty? ? nil : read_row(row_words, header)
        end
        build_lines(rows, header)
      end

      # Rows -> lines. A row with text but no amounts is either a section
      # heading (starts left of the serial column) or an item whose price sits
      # in a merged cell shared with its neighbours.
      def build_lines(rows, header)
        section = nil
        items = []
        rows.each do |row|
          break if [row[:task]].any? { |s| s.to_s.match?(/\A\W*(Sub\s*)?(Total|VAT)\b/i) } # summary rows under the table

          if row[:amounts].empty? && row[:text].present?
            if row[:min_x] < header[:left] + 70 && row[:quantity].nil? && row[:part_no].nil?
              section = row[:text]
              next
            end
            items << item(row, section)
          elsif row[:amounts].any?
            items << item(row, section)
          end
        end

        read_lone_prices(items)
        with_amounts = items.select { |i| i["line_total"] }
        shared = with_amounts.size == 1 && items.size >= 2 && items.count { |i| i["quantity"] } >= 2
        if shared
          package = with_amounts.first
          price = package["line_total"]
          package.merge!("unit_price" => nil, "line_total" => nil)
          items << { "section" => "Package price", "part_no" => nil,
                     "description" => "Price shared by the rows above (one merged price cell in the PO)",
                     "quantity" => 1, "unit_price" => price, "line_total" => price }
        end
        items
      end

      # A row whose total was unreadable but whose unit price was read ends up with
      # one amount (taken as the total). If that amount is a unit price used by
      # other rows, it is the unit price and the total is left to the validator.
      def read_lone_prices(items)
        prices = items.filter_map { |i| i["unit_price"] }.tally.select { |_p, n| n >= 2 }.keys
        items.each do |i|
          next unless i["unit_price"].nil? && i["quantity"] && i["line_total"] && prices.include?(i["line_total"])

          i["unit_price"] = i["line_total"]
          i["line_total"] = nil
        end
      end

      def item(row, section)
        { "section" => section, "part_no" => row[:part_no], "description" => row[:description],
          "quantity" => row[:quantity], "unit_price" => row[:unit], "line_total" => row[:total] }
      end

      def header_words(text_words)
        line = text_lines(text_words).find do |ws|
          joined = ws.map(&:text).join(" ")
          joined.match?(/Description|Scope/i) && joined.match?(/Price|Total/i)
        end
        return nil unless line

        unit = line.find { |w| w.text.match?(/\AUnit/i) }
        qty = line.find { |w| w.text.match?(/\AQty/i) } || above_word(text_words, line, /\A(Man|Qty|Quantity)\z/i)
        task = line.find { |w| w.text.match?(/\ATask\z/i) }
        scope = line.find { |w| w.text.match?(/\AScope\z/i) }
        { cy: line.sum(&:cy) / line.size, left: line.map(&:x).min - 30, right: line.map(&:right).max + 130,
          unit_x: unit&.x, qty_x: qty&.x, task_x: task&.x, scope_x: scope&.x, scope_w: scope&.w }
      end

      # A column title that tesseract put on its own line just above the header line ("Man" over "Day").
      def above_word(text_words, line, pattern)
        top = line.map(&:y).min
        text_words.find { |w| w.text.match?(pattern) && w.y < top && w.y > top - 140 }
      end

      def text_lines(text_words)
        text_words.group_by { |w| [w.block, w.par, w.line] }.values
      end

      # Where the table ends: the "Total Amount ...", "Amount in Words" or "Payment Terms" line.
      def table_end(text_words, header)
        stop = text_lines(text_words).select { |ws| ws.sum(&:cy) / ws.size > header[:cy] + 40 }
                                     .select { |ws| ws.map(&:text).join(" ").match?(/Total\s+Amount|Amount\s+in\s+Words|Payment\s+Terms/i) }
                                     .map { |ws| ws.map(&:y).min }.min
        stop ? stop - 6 : Float::INFINITY
      end

      def read_row(words, header)
        right_start = (header[:unit_x] || (header[:right] - 900)) - 140
        qty_start = (header[:qty_x] || (right_start - 380)) - 90
        amounts = []
        quantity = nil
        left = []

        ordered = text_lines(words).sort_by { |ws| ws.sum(&:cy) / ws.size }.flat_map { |ws| ws.sort_by(&:x) }
        ordered.each do |w|
          t = w.text.strip.gsub(/\A[|{\[(]+|[|}\])]+\z/, "")
          if w.x >= right_start && (t.match?(MONEY) || t.match?(DASH))
            amounts << [w.x, t.match?(DASH) ? 0.0 : Numbers.money(t)]
          elsif w.x >= qty_start && w.x < right_start && t.match?(/\A\d{1,4}\z/)
            quantity = t.to_i
          elsif w.x >= right_start
            next # stray OCR marks in the price columns
          elsif w.conf >= 1 && t.match?(/[\w&]/) && (t.length > 1 || t.match?(/[\d&]/))
            left << w # drops OCR debris ("|", "{", marks from the ruled lines)
          end
        end

        values = amounts.sort_by(&:first).map(&:last)
        if header[:task_x] && header[:scope_x] && header[:scope_w]
          return task_scope_row(left, values, quantity, header)
        end

        part_tokens, description_tokens = split_part(left)
        { amounts: values, quantity:, unit: values.size >= 2 ? values[-2] : nil, total: values.last,
          part_no: part_tokens.join.presence, description: description_tokens.join(" ").gsub(/\s+/, " ").strip,
          text: left.map(&:text).join(" ").strip, min_x: (left.map(&:x).min || header[:left]) }
      end

      # Tables with a "Task" and a "Scope" column (services priced per man-day):
      # the serial number is dropped and the description reads "Task - Scope".
      def task_scope_row(left, values, quantity, header)
        scope_center = header[:scope_x] + (header[:scope_w] / 2.0)
        right_edge = (header[:qty_x] || (scope_center + 600)) - 60
        scope_cut = (2 * scope_center) - right_edge - 30
        serial_cut = header[:task_x] - 220
        words = left.reject { |w| w.x < serial_cut }
        task = words.select { |w| w.x < scope_cut }.map { |w| clean(w.text) }
        scope = words.select { |w| w.x >= scope_cut }.map { |w| clean(w.text) }
        description = [task.join(" "), scope.join(" ")].map { |s| s.gsub(/\s+/, " ").strip }.reject(&:blank?).join(" - ")
        { amounts: values, quantity:, unit: values.size >= 2 ? values[-2] : nil, total: values.last,
          part_no: nil, description:, task: task.join(" "), text: left.map(&:text).join(" ").strip, min_x: (left.map(&:x).min || header[:left]) }
      end

      def clean(text)
        text.strip.gsub(/\A[|{\[(_]+|[|}\])]+\z/, "")
      end

      # SKU-looking tokens ("908-000462-003-" + "000") are the part number; the
      # serial column ("1", "2") is dropped; everything else is description.
      def split_part(left_words)
        parts = []
        description = []
        left_words.each_with_index do |w, i|
          t = w.text.strip.gsub(/\A[|{\[(]+|[|}\])]+\z/, "")
          if !t.match?(DATE) && (t.match?(SKU) || (parts.empty? && t.match?(/\A[A-Z]{2,}-[A-Z0-9-]+\z/)))
            parts << t
          elsif parts.any? && parts.last.end_with?("-") && t.match?(/\A\d{2,4}\z/)
            parts << t
          elsif i.zero? && t.match?(/\A\d{1,3}\z/) && left_words.size > 1
            next
          else
            description << t
          end
        end
        [parts, description]
      end
    end
  end
end
