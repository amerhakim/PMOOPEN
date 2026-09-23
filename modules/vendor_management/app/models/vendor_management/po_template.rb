module VendorManagement
  # Effectively a singleton row -- the editable header/footer text and
  # the PO PDF's block layout shown on every PO PDF export (REQ-PO-07's
  # "one single format, internal page to design/edit it"). Same
  # find_or_create singleton idiom as ApprovalChainTemplate.company_default.
  class PoTemplate < ApplicationRecord
    self.table_name = "vendor_management_po_templates"

    # "fixed" blocks have a real (x, y, w, h) and can be freely dragged
    # and resized on the designer canvas -- their content never grows.
    # "flow" blocks (the line-items table above all) can be 1 row or 50,
    # so only their horizontal position/width is meaningful; their
    # vertical stacking order relative to each other is what the
    # designer's reorder action actually changes (see "order" below).
    # Every block id here is the only ones PurchaseOrderPdf knows how to
    # render -- a tampered/malformed layout_json can never reference
    # anything else (see #layout's sanitizing below).
    BLOCK_IDS = %w[
      logo header_text title meta_block
      line_items_table totals_block notes_block end_user_block
      footer signature_block
    ].freeze

    FIXED_BLOCK_IDS = %w[logo header_text title meta_block footer signature_block].freeze
    FLOW_BLOCK_IDS = %w[line_items_table totals_block notes_block end_user_block].freeze

    # Mirrors this module's original hand-tuned Prawn coordinates
    # (see PurchaseOrderPdf's pre-designer version) so an untouched
    # template renders pixel-identical output to before this feature
    # existed. Page is A4 in points (595 x 842), origin bottom-left
    # (Prawn's own convention) -- y here is measured from the TOP for
    # designer-UI friendliness, converted when rendering.
    # Fixed blocks render on EVERY page (page: "all") -- matches the
    # original behaviour of render_page_header being called again on
    # page 2. Flow blocks belong to exactly one page ("page" => 1 or 2)
    # since their content (the line-items table vs. the signature
    # block) is genuinely different per page; "order" is only compared
    # within the same page's flow blocks.
    # Every x here is LOCAL to the printable margin box (0..515, since
    # A4 is 595pt wide minus this PDF's 40pt left/right margins) -- NOT
    # an offset from the physical page edge. The original pre-designer
    # code drew everything at the top-level bounds' own origin (x=0),
    # except header_text (explicitly offset past the logo's width +
    # a 20pt gap). Every block below except header_text must keep x=0
    # for this reason -- an x=40 here (as this constant briefly had)
    # double-applies the margin and pushes a full-width block off the
    # right edge of the printable area by exactly that same 40pt.
    DEFAULT_LAYOUT = [
      { "id" => "logo", "kind" => "fixed", "page" => "all", "x" => 0, "y" => 40, "w" => 90, "h" => 55, "visible" => true },
      { "id" => "header_text", "kind" => "fixed", "page" => "all", "x" => 110, "y" => 40, "w" => 405, "h" => 55, "visible" => true },
      { "id" => "title", "kind" => "fixed", "page" => "all", "x" => 0, "y" => 95, "w" => 515, "h" => 30, "visible" => true },
      { "id" => "meta_block", "kind" => "fixed", "page" => "all", "x" => 0, "y" => 135, "w" => 515, "h" => 90, "visible" => true },
      { "id" => "footer", "kind" => "fixed", "page" => "all", "x" => 0, "y" => 780, "w" => 515, "h" => 30, "visible" => true },
      { "id" => "line_items_table", "kind" => "flow", "page" => 1, "order" => 1, "x" => 0, "w" => 515, "visible" => true },
      { "id" => "totals_block", "kind" => "flow", "page" => 1, "order" => 2, "x" => 0, "w" => 515, "visible" => true },
      { "id" => "notes_block", "kind" => "flow", "page" => 1, "order" => 3, "x" => 0, "w" => 515, "visible" => true },
      { "id" => "end_user_block", "kind" => "flow", "page" => 1, "order" => 4, "x" => 0, "w" => 515, "visible" => true },
      { "id" => "signature_block", "kind" => "flow", "page" => 2, "order" => 1, "x" => 0, "w" => 515, "visible" => true }
    ].freeze

    def self.current
      first || create!(
        header_text: "Qatar Datamation Systems W.L.L",
        header_text_ar: "قطر لأنظمة الكمبيوتر ذ.م.م",
        footer_text: ""
      )
    end

    # Parsed, sanitized layout -- always returns a real, renderable
    # array of block hashes. Falls back to DEFAULT_LAYOUT whenever
    # layout_json is blank, isn't valid JSON, or (after parsing) ends
    # up missing/duplicating/misnaming a block -- rather than ever
    # handing PurchaseOrderPdf something it doesn't know how to render.
    def layout
      parsed = layout_json.present? ? JSON.parse(layout_json) : nil
      sanitized = sanitize_layout(parsed)
      sanitized || DEFAULT_LAYOUT
    rescue JSON::ParserError
      DEFAULT_LAYOUT
    end

    def layout=(value)
      self.layout_json = value.is_a?(String) ? value : value.to_json
    end

    private

    def sanitize_layout(parsed)
      return nil unless parsed.is_a?(Array)

      blocks = parsed.select { |b| b.is_a?(Hash) && BLOCK_IDS.include?(b["id"]) }
      return nil unless blocks.map { |b| b["id"] }.sort == BLOCK_IDS.sort

      blocks
    end
  end
end
