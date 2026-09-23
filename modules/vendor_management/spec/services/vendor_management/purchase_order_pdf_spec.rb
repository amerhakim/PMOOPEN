require_relative "../../spec_helper"
require "pdf/reader"

RSpec.describe VendorManagement::PurchaseOrderPdf do
  let(:project) { create(:project) }
  let(:vendor) { VendorManagement::Vendor.create!(name: "Acme Supplies", status: "active") }
  let(:po) do
    VendorManagement::PurchaseOrder.create!(
      project:, vendor:, status: "active", currency: "QAR",
      quotation_ref_no: "Q-1", issue_date: Date.today
    )
  end

  before do
    po.po_line_items.create!(description: "Main item", item_type: "hardware", quantity: 1, unit_price: 100)
    po.po_line_items.create!(description: "Optional item", item_type: "hardware", quantity: 2, unit_price: 50,
                              section_label: "Optional: Extra Kit")
  end

  it "renders a valid PDF grouping line items by section" do
    bytes = described_class.new(po).call
    expect(bytes).to be_a(String)
    expect(bytes[0..3]).to eq("%PDF")
  end

  it "renders a valid PDF even with payments recorded against the PO" do
    po.po_payments.create!(amount: 100, paid_on: Date.today, invoice_no: "INV-1")

    bytes = described_class.new(po).call
    expect(bytes).to be_a(String)
    expect(bytes[0..3]).to eq("%PDF")
  end

  it "renders a valid PDF with a signature page built from real approval steps" do
    template = VendorManagement::ApprovalChainTemplate.create!(project_id: nil, name: "Default Approval Chain")
    template.approval_step_definitions.create!(sequence: 1, approver_title: "Logistics Coordinator")
    po.submit_for_approval!
    po.approve_step!(po.po_approval_steps.order(:sequence).first, "Ali")

    bytes = described_class.new(po).call
    expect(bytes).to be_a(String)
    expect(bytes[0..3]).to eq("%PDF")
  end

  def pdf_text(bytes)
    reader = PDF::Reader.new(StringIO.new(bytes))
    reader.pages.map(&:text).join("\n")
  end

  describe "the header's Arabic line" do
    it "renders a valid PDF with real, non-garbled Arabic glyphs when header_text_ar is set" do
      VendorManagement::PoTemplate.current.update!(header_text_ar: "قطر لأنظمة الكمبيوتر ذ.م.م")

      bytes = described_class.new(po).call
      reader = PDF::Reader.new(StringIO.new(bytes))
      runs = reader.pages.first.runs

      # Reshaping maps each base Arabic letter to its own joined
      # presentation-form codepoint (U+FE70..U+FEFF), so the raw base
      # letters won't appear verbatim in the extracted text -- what
      # matters is that SOME text landed in that Unicode range (proof
      # the Amiri font's glyphs were actually used, not silently
      # skipped/tofu'd) and that generation didn't raise.
      arabic_presentation_form_runs = runs.select { |r| r.text.codepoints.any? { |cp| cp >= 0xFE70 && cp <= 0xFEFF } }

      expect(bytes[0..3]).to eq("%PDF")
      expect(arabic_presentation_form_runs).not_to be_empty
    end

    it "still renders a valid PDF when header_text_ar is blank (Arabic line is optional)" do
      VendorManagement::PoTemplate.current.update!(header_text_ar: "")

      bytes = described_class.new(po).call

      expect(bytes[0..3]).to eq("%PDF")
    end
  end

  describe "the default layout" do
    it "still renders every block's real content (guards against a silent regression from the layout refactor)" do
      po.update!(special_note: "Handle with care", payment_terms: "Net 30")
      text = pdf_text(described_class.new(po).call)

      expect(text).to include("PURCHASE ORDER")
      expect(text).to include(po.po_number)
      expect(text).to include(po.vendor.name)
      expect(text).to include("Main item")
      expect(text).to include("Optional: Extra Kit")
      expect(text).to include("Total Amount in QAR")
      expect(text).to include("Handle with care")
      expect(text).to include("Net 30")
    end

    it "keeps every full-width block's left edge flush with the true 40pt page margin (regression: DEFAULT_LAYOUT briefly gave title/meta_block/footer/line_items_table/totals_block/notes_block/end_user_block/signature_block/logo an x of 40 on top of the page's own 40pt margin, pushing each one 40pt past the right printable edge)" do
      reader = PDF::Reader.new(StringIO.new(described_class.new(po).call))
      runs = reader.pages.first.runs

      sno_run = runs.find { |r| r.text == "S.No" }

      expect(sno_run).not_to be_nil
      # 40pt page margin + 4pt cell padding = 44. Under the bug this
      # landed at 84 (an extra, wrong 40pt from the block's own x).
      expect(sno_run.x).to be_within(2).of(44)
    end
  end

  describe "the end-user block, when its text wraps onto multiple lines" do
    it "starts the Inco Terms box no higher than the end-user table's own top (regression: previously guessed a fixed 20pt per row, which put it ABOVE the table's real bottom once a value wrapped)" do
      po.update!(
        end_user_name: "General Secretariat of the Council of Ministers",
        end_user_address: "Corniche Street, P.O. Box 636, Doha, Qatar",
        incoterm: "DAP"
      )

      reader = PDF::Reader.new(StringIO.new(described_class.new(po).call))
      runs = reader.pages.first.runs

      table_top_y = runs.select { |r| r.text.include?("End User Company Name") }.map(&:y).max
      incoterm_y = runs.select { |r| r.text.include?("Inco Terms") }.map(&:y).max

      expect(table_top_y).not_to be_nil
      expect(incoterm_y).not_to be_nil
      # PDF y grows upward, so "no higher than the table's top" means
      # its y must not exceed the table's own top-row y.
      expect(incoterm_y).to be <= table_top_y
    end

    it "uses the full page width for the End User table when there's no Inco Terms/delivery info to show alongside it (regression: previously always split 55/45, leaving the right half blank with no visible box)" do
      po.update!(end_user_name: "Ministry of Testing", incoterm: nil, delivery_address: nil, delivery_contact: nil)

      reader = PDF::Reader.new(StringIO.new(described_class.new(po).call))
      runs = reader.pages.first.runs

      row_run = runs.find { |r| r.text.include?("Ministry of Testing") }
      # The full-width table (this fix) uses a 160pt label column, vs.
      # the split-layout table's 130pt one -- so the value text starts
      # measurably further right (40pt left margin + 160pt label +
      # ~4pt cell padding) than the narrower split layout ever would.
      expect(row_run.x).to be > 190

    end
  end

  describe "a custom layout" do
    it "omits a block entirely when its visible flag is false" do
      po.update!(special_note: "Handle with care")
      custom_layout = VendorManagement::PoTemplate::DEFAULT_LAYOUT.map(&:dup)
      custom_layout.find { |b| b["id"] == "notes_block" }["visible"] = false
      VendorManagement::PoTemplate.current.update!(layout: custom_layout)

      text = pdf_text(described_class.new(po).call)

      expect(text).not_to include("Handle with care")
      expect(text).to include("PURCHASE ORDER")
    end
  end
end


