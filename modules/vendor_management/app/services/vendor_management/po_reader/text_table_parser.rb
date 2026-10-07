module VendorManagement
  module PoReader
    # Reads the items table of a PO from its TEXT (the PDF's own text layer, or
    # the OCR text), whatever the supplier's layout is. The table is found by its
    # header line (any line with at least three recognised column titles such as
    # "Product Number", "Description", "Qty", "Unit Price", "Total Price"), the
    # columns are taken from where those titles sit, and each following line is
    # assigned to a column by its position. No language model is needed.
    class TextTableParser
      Cell = Struct.new(:text, :start, :finish)
      Column = Struct.new(:group, :text, :start, :finish)

      PART = /\A(product\s*(number|no\.?|code|#)|part\s*(no\.?|number|#)|sku|item\s*(no\.?|code|number|#)|material(\s*(no\.?|number))?|article(\s*no\.?)?|model)\z/i
      DESC = /\A((item|product)\s*)?(description|details?|name)\z|\A(scope|task|particulars)\z/i
      QTY = /\A(qty\.?|quantity|ord(er)?\s*qty\.?|units?|man\s*days?|no\.?\s*of\s*units)\z/i
      UNIT = /\A(unit\s*(price|cost|rate)|net\s*(unit\s*)?price|offering|bd\s*net|rate|price)\z/i
      LIST = /\Alist\s*pr/i
      TOTAL = /\A(total(\s*(price|amount|value|cost))?|amount|line\s*total|extended(\s*price)?|net\s*total)\z/i

      STOP = /special\s+terms|terms\s+(and|&)\s+conditions|grand\s*total|(sub\s*)?total\s*(price|amount|value)?\s*(in\s+[a-z]{3})?\s*[:.]?\s*([a-z]{3}\s*)?[\d]|amount\s+in\s+words|payment\s+terms?\s*[:.]/i
      SKU = /\A(?=.*[0-9\-])[A-Z0-9][A-Z0-9\-_.\/#]{2,}\z/i
      NUMBER = /\A\(?\d[\d,]*(\.\d+)?\)?\z/

      def initialize(text)
        @lines = text.to_s.tr("\f", "\n").lines.map(&:chomp)
      end

      # => array of line hashes ("section", "part_no", "description", "quantity", "unit_price", "line_total")
      def call
        rows = collect_rows
        lines = rows.filter_map { |row| to_line(row) }
        lines = drop_option_rows(lines)
        keep_package_only(lines)
      rescue StandardError
        []
      end

      private

      def cells(line)
        line.to_enum(:scan, /\S+(?: \S+)*/).map do
          m = Regexp.last_match
          Cell.new(m[0], m.begin(0), m.end(0))
        end
      end

      def group_of(text)
        t = text.strip.sub(/\A(sn|s\.?\s*no\.?|sr\.?|no\.?|#)\s+/i, "") # a serial-number title stuck to the next title
        return :part if t.match?(PART)
        return :desc if t.match?(DESC)
        return :qty if t.match?(QTY)
        return :unit if t.match?(UNIT)
        return :list if t.match?(LIST)
        return :total if t.match?(TOTAL)

        :other
      end

      def header?(line)
        groups = cells(line).map { |c| group_of(c.text) }.uniq - [:other]
        groups.include?(:desc) && groups.size >= 3
      end

      def columns_for(index)
        found = cells(@lines[index]).map { |c| Column.new(group_of(c.text), c.text, c.start, c.finish) }
        # without a net/offering price column, the list price column is the unit price
        found.each { |c| c.group = :unit if c.group == :list } unless found.any? { |c| c.group == :unit }
        # "ProductName" next to a "Description" column holds the product code, not the description
        names = found.select { |c| c.group == :desc }
        names.first.group = :part if names.size > 1 && names.first.text.match?(/name/i) && found.none? { |c| c.group == :part }
        extra = [index - 2, index - 1, index + 1].reject { |i| i.negative? || @lines[i].nil? || !header_like?(@lines[i]) }.flat_map do |i|
          cells(@lines[i]).filter_map do |c|
            next if c.text.match?(/\d/) || found.any? { |f| (f.start - c.start).abs <= 4 }

            Column.new(:other, c.text, c.start, c.finish)
          end
        end
        (found + extra).sort_by(&:start)
      end

      # a title line has no part number and no amounts in it (a data row does)
      def header_like?(line)
        cs = cells(line)
        cs.any? && !data_line?(line) && cs.none? { |c| c.text.match?(/\A\d[\d,]*(\.\d+)?\z/) }
      end

      def data_line?(line)
        first = cells(line).first
        first && first.text.match?(SKU)
      end

      def collect_rows
        rows = []
        columns = nil
        anchors = []
        pending = []
        @lines.each_with_index do |line, i|
          if header?(line)
            columns = columns_for(i)
            @roles = columns.map(&:group).select { |g| %i[qty list unit total].include?(g) }
            next
          end
          next if columns.nil?

          if line.match?(STOP)
            columns = nil
            next
          end
          next if line.strip.empty?

          assigned = assign(cells(line), columns)
          last = rows.last
          near = last && i - last[:index] <= 2
          if anchor_line?(assigned)
            rows << { index: i, fields: assigned, extra: [], part_extra: [] }
          elsif near && assigned[:numbers].present? && assigned.except(:numbers, :other).values.none?(&:present?)
            last[:fields][:numbers].concat(assigned[:numbers]) # an amount that wrapped onto the next line
          else
            # a product code that wrapped onto the next line ("SFP-PLUS-SR-" / "XCVR")
            if near && assigned[:numbers].blank? && assigned[:part].size == 1 && wrapped_part?(last, assigned[:part].first)
              last[:part_extra] << assigned[:part].first
            end
            text = assigned[:desc].join(" ")
            if assigned[:desc].present? && (assigned.keys & %i[qty unit total numbers]).none? { |k| assigned[k].present? } && !text.match?(/\bID\s*:/i)
              pending << { index: i, text: }
            end
          end
        end
        attach_descriptions(rows, pending)
        rows
      end

      def wrapped_part?(row, text)
        previous = row[:fields][:part].first.to_s
        text.match?(/\A[A-Za-z0-9\-_.\/]+\z/) && (previous.end_with?("-") || !previous.match?(SKU))
      end

      # A description line belongs to the row before it when that row already starts its
      # description on its own line (the usual layout); with text centred in tall cells
      # (the row's own line has none) it goes to the nearer row.
      def attach_descriptions(rows, pending)
        pending.each do |p|
          before = rows.reverse.find { |r| r[:index] < p[:index] }
          after = rows.find { |r| r[:index] > p[:index] }
          row =
            if before.nil? then after
            elsif after.nil? then before
            elsif before[:fields][:desc].present? && after[:fields][:desc].present? then before
            else
              (p[:index] - before[:index]) <= (after[:index] - p[:index]) ? before : after
            end
          next if row.nil? || (row[:index] - p[:index]).abs > (row[:fields][:desc].present? ? 14 : 4)

          row[:extra] << p
        end
      end

      YEAR = /\A(19|20)\d{2}\z/ # the year of a date wrapped onto its own line, not a quantity
      NUM_CELL = /\A(?:(?:[A-Z]{3}|[$€£])\s*)?(-?\(?\d[\d,]*(?:\.\d+)?\)?)(?:\s+(?:BD\s*Net|net|each|ea|usd|qar|sar|omr)\b.*)?\z/i

      # Text goes by column position (with some slack: the text layout drifts);
      # numbers are kept in reading order and given their roles in to_line.
      def assign(row_cells, columns)
        out = Hash.new { |h, k| h[k] = [] }
        row_cells.each do |c|
          if !c.text.match?(YEAR) && (m = c.text.match(NUM_CELL))
            out[:numbers] << Numbers.parse(m[1])
          else
            col = columns.select { |x| x.start - lead(x, columns) <= c.start }.max_by(&:start) || columns.first
            text = col&.group == :part ? c.text.sub(/\A\d{1,3}\s+(?=\S)/, "") : c.text # "10 SFP-..." -> the serial number is not part of the code
            out[col.group] << text if col
          end
        end
        out
      end

      # how far left of its title a column's text may start: a third of the gap to the
      # column before it, at most 12 (the text layout drifts by a few characters)
      def lead(column, columns)
        before = columns.select { |x| x.start < column.start }.max_by(&:start)
        before ? [(column.start - before.start) / 3, 12].min : 12
      end

      # a row is a line with amounts and a product code or a description
      def anchor_line?(assigned)
        assigned[:numbers].present? && (assigned[:part].present? || assigned[:desc].present?)
      end

      def to_line(row)
        f = row[:fields]
        before = row[:extra].select { |e| e[:index] < row[:index] }.map { |e| e[:text] }
        after = row[:extra].select { |e| e[:index] > row[:index] }.map { |e| e[:text] }
        description = (before + f[:desc] + after).join(" ").gsub(/\s+/, " ").strip
        return nil if description.blank? && f[:part].blank?

        values = f[:numbers].last(@roles.size)
        by_role = @roles.last(values.size).zip(values).to_h
        quantity = by_role[:qty]&.abs
        unit = by_role[:unit] # a discount line has a negative price
        total = by_role[:total]
        total ||= (quantity * unit).round(2) if quantity && unit
        part = row[:part_extra].to_a.reduce(f[:part].first.to_s) { |acc, more| acc.end_with?("-") ? "#{acc}#{more}" : "#{acc} #{more}" }.strip.presence
        # many quotes repeat the product code as the first words of the description
        description = description.delete_prefix(part).strip if part && description.start_with?(part) && description.length > part.length
        { "section" => nil, "part_no" => part, "description" => description, "quantity" => quantity,
          "unit_price" => unit, "line_total" => total }
      end

      # "Factory Integrated" option rows repeat the product number with no price.
      def drop_option_rows(lines)
        return lines unless lines.any? { |l| l["unit_price"].to_f.positive? }

        previous = nil
        lines.reject do |l|
          dup = previous && l["part_no"].present? && l["part_no"] == previous["part_no"] && l["unit_price"].to_f.zero? && l["line_total"].to_f.zero?
          previous = l
          dup
        end
      end

      # A bundle: the first line carries the price of the whole package and the
      # lines after it are its parts, whose prices add up to it. Keep the package.
      def keep_package_only(lines)
        return lines if lines.size < 3

        head = lines.first["line_total"].to_f
        rest = lines.drop(1).sum { |l| l["line_total"].to_f }
        return lines unless head.positive? && (head - rest).abs <= [head * 0.01, 1.0].max

        [lines.first.merge("description" => "#{lines.first['description']} (bundle price; its #{lines.size - 1} parts are included)")]
      end
    end
  end
end
