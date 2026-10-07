module VendorManagement
  module PoReader
    # Number and date parsing that survives OCR noise ("8.250.00", "$ 1,425.00",
    # "10-Sep-26") and spreadsheet cells that are already numbers or dates.
    module Numbers
      module_function

      def parse(value)
        return nil if value.nil?
        return value.to_f.round(4) if value.is_a?(Numeric)

        s = value.to_s.strip
        return nil if s.empty? || s.match?(/\A[-–—\s]+\z/)

        negative = s.start_with?("(") && s.end_with?(")") || s.start_with?("-")
        s = s.gsub(/[^\d.,]/, "")
        return nil if s.empty?

        # the last separator is the decimal point only when 1-2 digits follow it
        number = if (m = s.match(/[.,](\d{1,2})\z/))
                   "#{s[0...m.begin(0)].delete('.,')}.#{m[1]}".to_f
                 else
                   s.delete(".,").to_f
                 end
        negative ? -number : number
      end

      def money(value)
        n = parse(value)
        n&.round(2)
      end

      def date(value)
        return nil if value.nil?
        return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

        s = value.to_s.strip.gsub(/\s+/, "")
        return nil if s.empty?

        %w[%d-%b-%y %d-%b-%Y %d/%b/%y %d/%b/%Y %d/%m/%Y %d/%m/%y %Y-%m-%d %d.%m.%Y].each do |fmt|
          date = Date.strptime(s, fmt)
          return date if date.year >= 100 # "25/08/26" is 2026, not the year 26
        rescue ArgumentError
          next
        end
        Date.parse(s)
      rescue ArgumentError, TypeError
        nil
      end

      def percent(value)
        n = parse(value.to_s.delete("%"))
        n && n.positive? && n <= 100 ? n : nil
      end
    end
  end
end
