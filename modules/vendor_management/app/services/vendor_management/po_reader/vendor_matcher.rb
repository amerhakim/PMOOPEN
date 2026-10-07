module VendorManagement
  module PoReader
    # Finds the vendor in the Vendor Master that a supplier name on a PO most
    # likely means ("GULF IT NETWORK DISTRIBUTION FZ LLC" ~ "Gulf IT Network
    # Distribution"). Pure string work so it is fast and predictable.
    class VendorMatcher
      NOISE = %w[llc wll w l l fz fze fzc fzco co company ltd limited inc est establishment trading the and for of qatar].freeze
      SUGGEST_AT = 0.75

      def initialize(vendors = VendorManagement::Vendor.all)
        @vendors = vendors.to_a
      end

      # => { "id" =>, "name" =>, "score" => } or nil
      def match(supplier_name)
        wanted = tokens(supplier_name)
        return nil if wanted.empty?

        best = @vendors.map { |v| [v, score(wanted, tokens(v.name))] }.max_by { |_, s| s }
        return nil if best.nil? || best[1] < SUGGEST_AT

        { "id" => best[0].id, "name" => best[0].name, "score" => best[1].round(2) }
      end

      def tokens(name)
        name.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").split.reject { |t| NOISE.include?(t) || t.length < 2 }.uniq
      end

      private

      def score(a, b)
        return 0.0 if a.empty? || b.empty?

        common = (a & b).size.to_f
        return 1.0 if a.sort == b.sort

        jaccard = common / (a | b).size
        containment = common / [a.size, b.size].min
        [jaccard, containment * 0.9].max
      end
    end
  end
end
