require "arabic-letter-connector"

module VendorManagement
  # Renders a PO to PDF matching the user-supplied reference document
  # (QDS-CMSG-335-671.pdf) as closely as practical: logo + header text,
  # title, meta block, a line-items table grouped into labeled sections
  # (S.No restarting per group), totals with amount-in-words
  # (REQ-PO-09), End User/Inco Terms block, a footer, and a second page
  # with a signature block built from the PO's own approval steps.
  #
  # Deliberately a plain Prawn::Document wrapper, not a subclass of
  # anything under Exports::PDF::Common -- that machinery is built for
  # multi-page WorkPackage table/Gantt/TOC exports and is tightly coupled
  # to WorkPackage/Queries::WorkPackages concepts that don't apply to a
  # one-page PO document. The logo comes from the QDS logo already
  # uploaded via modules/custom_branding (the same one shown in the
  # app's own top nav) -- deliberately NOT core's Exports::PDF::Common::Logo,
  # which falls back to OpenProject's own default logo when no custom
  # one is configured; this PDF renders no logo at all in that case
  # instead, never an OpenProject brand mark on a business document.
  #
  # Layout-driven since the PDF designer feature: every block's
  # position/size/order/visibility comes from PoTemplate#layout (see
  # PoTemplate::DEFAULT_LAYOUT for the shape and the fixed-vs-flow
  # split rationale -- fixed blocks get a real x/y/w/h, flow blocks
  # only x/w plus a page-scoped order, since their height depends on
  # the PO's actual data). Each block's own draw_<id> method only
  # draws WITHIN whatever bounding box render_fixed_block/render_flow_block
  # already positioned it in -- it never reaches for absolute page
  # coordinates itself.
  class PurchaseOrderPdf
    LABEL_COLOR = "555555".freeze
    LINE_COLOR = "CCCCCC".freeze

    # Prawn has no Arabic script shaping/bidi of its own -- raw Arabic
    # characters would draw as disconnected isolated letterforms in
    # left-to-right order. ArabicLetterConnector reshapes each letter
    # into its correct joined presentation form (still in logical/
    # reading order); reversing that result afterwards is the standard
    # workaround to get correct right-to-left visual order out of a
    # renderer that only ever draws left-to-right (see #shape_arabic).
    # Amiri is a real Arabic-script font with full coverage of the
    # resulting presentation-form glyphs -- core's bundled Noto Sans
    # does not include Arabic at all (confirmed directly against its
    # cmap), so this ships its own font files rather than reusing one.
    ARABIC_FONT_DIR = Rails.root.join("modules", "vendor_management", "app", "assets", "fonts")

    def initialize(purchase_order)
      @po = purchase_order
      @template = PoTemplate.current
      @layout = @template.layout
    end

    def call
      Prawn::Document.new(page_size: "A4", margin: [40, 40, 50, 40]) do |doc|
        @pdf = doc
        register_arabic_font
        render_page(1)
        pdf.start_new_page
        render_page(2)
      end.render
    end

    private

    attr_reader :pdf, :po, :template, :layout

    def render_page(page_number)
      fixed_blocks = layout.select { |b| b["kind"] == "fixed" && b["visible"] }
      flow_blocks = layout.select { |b| b["kind"] == "flow" && b["page"] == page_number && b["visible"] }
                           .sort_by { |b| b["order"].to_i }

      fixed_blocks.each { |block| render_fixed_block(block) }

      flow_start_y = fixed_blocks.reject { |b| b["id"] == "footer" }
                                  .map { |b| b["y"].to_f + b["h"].to_f }.max || 0
      pdf.move_cursor_to(pdf.bounds.top - flow_start_y)

      flow_blocks.each { |block| render_flow_block(block) }
    end

    def render_fixed_block(block)
      x = block["x"].to_f
      y = pdf.bounds.top - block["y"].to_f
      pdf.bounding_box([x, y], width: block["w"].to_f, height: block["h"].to_f) do
        draw_block(block["id"])
      end
    end

    def render_flow_block(block)
      return if pdf.cursor <= 0

      pdf.bounding_box([block["x"].to_f, pdf.cursor], width: block["w"].to_f) do
        draw_block(block["id"])
      end
    end

    def draw_block(id)
      send("draw_#{id}")
    end

    def draw_logo
      image_obj, image_info = logo_image
      return unless image_obj

      pdf.embed_image image_obj, image_info, at: [0, pdf.bounds.top], width: pdf.bounds.width
    end

    # Overrides what Exports::PDF::Common::Logo#logo_image would do --
    # never falls back to core's own default OpenProject logo image.
    # Uses the QDS logo already uploaded via modules/custom_branding,
    # matching what the app's own top nav already shows everywhere;
    # renders no logo at all if that hasn't been configured, rather
    # than a stray OpenProject brand mark on a business document.
    def logo_image
      filename = custom_branding_logo_filename
      return [nil, nil] unless filename

      pdf.build_image_object(filename)
    end

    def custom_branding_logo_filename
      setting = CustomBranding::Setting.current
      return unless setting&.logo&.present?

      file = setting.logo.file
      return unless file&.exists?

      content_type = OpenProject::ContentTypeDetector.new(file.path).detect
      return unless %w[image/jpeg image/png image/gif image/webp].include?(content_type)

      file.path
    rescue StandardError => e
      Rails.logger.error "Failed to access custom_branding PDF logo file: #{e}"
      nil
    end

    def draw_header_text
      if template.header_text_ar.present?
        pdf.font "Amiri" do
          pdf.text shape_arabic(template.header_text_ar), align: :right, size: 13, style: :bold
        end
      end
      pdf.text template.header_text.to_s, align: :right, size: 12, style: :bold
    end

    def register_arabic_font
      pdf.font_families.update(
        "Amiri" => {
          normal: ARABIC_FONT_DIR.join("Amiri-Regular.ttf").to_s,
          bold: ARABIC_FONT_DIR.join("Amiri-Bold.ttf").to_s
        }
      )
    end

    # Reshapes Arabic text into its correct joined presentation forms,
    # then reverses it -- Prawn always draws left-to-right, so a
    # right-to-left script's visual reading order has to already be
    # baked into the character sequence before it reaches Prawn.
    def shape_arabic(text)
      ArabicLetterConnector.transform(text).reverse
    end

    def draw_title
      pdf.stroke_color LINE_COLOR
      pdf.stroke_horizontal_rule
      pdf.move_down 12
      pdf.text "PURCHASE ORDER", align: :center, size: 18, style: :bold
    end

    def draw_meta_block
      pdf.text format_date(po.issue_date).to_s, size: 10
      pdf.text "To:", size: 10
      pdf.text "Supplier Name:  <b>#{escape(po.vendor.name)}</b>", inline_format: true, size: 10
      pdf.text "Purchase Order No.  <b>#{escape(po.po_number)}</b>", inline_format: true, size: 10, align: :center
      pdf.move_down 6
      pdf.text "Quotation Reference No.: #{escape(po.quotation_ref_no)}", size: 10
    end

    def draw_line_items_table
      groups = po.po_line_items.order(:id).to_a.chunk_while { |a, b| a.section_label == b.section_label }

      header = ["S.No", "Part No.", "Description", "Qty", "Unit Price", "Total Price"]
      rows = [header]
      row_styles = { 0 => { background_color: "E8E8E8", font_style: :bold } }

      groups.each do |group|
        if group.first.section_label.present?
          rows << [{ content: group.first.section_label, colspan: 6, font_style: :bold, background_color: "F0F0F0" }]
          row_styles[rows.size - 1] = { background_color: "F0F0F0", font_style: :bold }
        end

        group.each_with_index do |item, idx|
          rows << [
            (idx + 1).to_s,
            item.part_no.to_s,
            item.description.to_s,
            number_with_delimiter(item.quantity),
            number_with_delimiter(item.unit_price, decimals: 2),
            number_with_delimiter(item.line_total, decimals: 2)
          ]
        end
      end

      pdf.table(rows, header: true, width: pdf.bounds.width,
                      column_widths: { 0 => 35, 3 => 40, 4 => 70, 5 => 75 },
                      cell_style: { size: 9, border_color: LINE_COLOR, padding: [4, 4, 4, 4] }) do |table|
        row_styles.each do |row_index, style|
          table.row(row_index).style(style) if row_index < table.row_length
        end
        table.columns(2).width = pdf.bounds.width - 35 - 40 - 70 - 75 - 70
      end
    end

    def draw_totals_block
      rows = [
        [
          { content: "Total Amount in #{po.currency}", font_style: :bold },
          { content: number_with_delimiter(po.total_value, decimals: 2), font_style: :bold, align: :right }
        ],
        ["Amount in Words:", AmountInWords.new(po.total_value, po.currency).call]
      ]
      draw_label_value_table(rows)
    end

    def draw_notes_block
      rows = []
      rows << ["Special Note:", po.special_note.to_s] if po.special_note.present?
      rows << ["Payment Terms:", po.payment_terms.to_s] if po.payment_terms.present?
      rows << ["Delivery:", po.expected_end_date ? format_date(po.expected_end_date) : ""]
      draw_label_value_table(rows)
    end

    # Bordered two-column label/value table -- matches the reference
    # document's boxed layout for the totals/amount-in-words/notes
    # section, rather than the loose unbordered text lines this used
    # to render as.
    def draw_label_value_table(rows)
      pdf.table(rows, width: pdf.bounds.width, column_widths: { 0 => 160 },
                      cell_style: { size: 9, border_color: LINE_COLOR, padding: [4, 6, 4, 6] }) do |table|
        table.columns(0).font_style = :bold
      end
    end

    def draw_end_user_block
      end_user_rows = [
        ["End User Company Name", po.end_user_name.to_s],
        ["P.O. Box Address", po.end_user_address.to_s],
        ["End User Contact Name", po.end_user_contact_name.to_s],
        ["Contact No/Fax No", po.end_user_contact_phone.to_s],
        ["Contact E-mail ID", po.end_user_contact_email.to_s]
      ]

      incoterm_text = [
        po.incoterm.present? ? "Inco Terms: #{po.incoterm}" : nil,
        po.delivery_address.presence,
        po.delivery_contact.presence
      ].compact.join("\n")

      # With nothing to show in the Inco Terms box, splitting the row
      # 55/45 just leaves the right half of the page blank with no
      # visible box outline -- let the End User table use the full
      # width instead, matching the totals/notes table above it.
      unless incoterm_text.present?
        pdf.table(end_user_rows, width: pdf.bounds.width,
                                  cell_style: { size: 8.5, border_color: LINE_COLOR, padding: [3, 4, 3, 4] }) do |table|
          table.columns(0).font_style = :bold
          table.columns(0).width = 160
        end
        return
      end

      left_width = pdf.bounds.width * 0.55
      start_y = pdf.cursor

      pdf.bounding_box([0, start_y], width: left_width) do
        pdf.table(end_user_rows, cell_style: { size: 8.5, border_color: LINE_COLOR, padding: [3, 4, 3, 4] }) do |table|
          table.columns(0).font_style = :bold
          table.columns(0).width = 130
        end
      end
      left_bottom = pdf.cursor

      pdf.bounding_box([left_width + 10, start_y], width: pdf.bounds.width - left_width - 10) do
        pdf.text incoterm_text, size: 8.5
        pdf.stroke_bounds
      end
      right_bottom = pdf.cursor

      # Neither box's real rendered height is known ahead of time (a
      # long end-user name/address wraps to extra lines) -- measuring
      # both AFTER drawing and moving the shared cursor to whichever
      # ended lower avoids the two boxes overlapping, regardless of how
      # much either one's text wraps. The previous fixed "20pt per row"
      # guess broke the instant a real value here was long enough to
      # wrap onto a second line.
      pdf.move_cursor_to [left_bottom, right_bottom].min
    end

    def draw_footer
      pdf.stroke_color LINE_COLOR
      pdf.stroke_horizontal_rule
      pdf.move_down 4
      pdf.text template.footer_text.to_s, size: 8, align: :center, color: LABEL_COLOR
    end

    def draw_signature_block
      steps = po.po_approval_steps.order(:sequence)
      return if steps.empty?

      column_width = pdf.bounds.width / steps.size.clamp(1, 4)
      steps.each_slice(4) do |row_steps|
        row_steps.each_with_index do |step, idx|
          pdf.bounding_box([idx * column_width, pdf.cursor], width: column_width - 10) do
            pdf.move_down 40
            pdf.stroke_horizontal_rule
            pdf.move_down 4
            pdf.text step.approver_name.to_s, size: 9, style: :bold if step.status == "approved"
            pdf.text step.approver_title.to_s, size: 9
          end
        end
        pdf.move_down 90
      end
    end

    def escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def format_date(date)
      return "" unless date

      date.strftime("%d-%b-%y")
    end

    def number_with_delimiter(number, decimals: 0)
      return "" if number.nil?

      whole, frac = number.to_f.round(decimals).to_s.split(".")
      whole = whole.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
      decimals.positive? ? "#{whole}.#{(frac || '0' * decimals).ljust(decimals, '0')}" : whole
    end
  end
end
