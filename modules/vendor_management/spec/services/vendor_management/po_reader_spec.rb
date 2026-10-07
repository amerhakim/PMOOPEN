require "caxlsx"
require_relative "../../spec_helper"

RSpec.describe VendorManagement::PoReader do
  describe VendorManagement::PoReader::Numbers do
    it "reads amounts the way OCR and spreadsheets print them" do
      expect(described_class.money("72,890.00")).to eq(72_890.0)
      expect(described_class.money("8.250.00")).to eq(8250.0)
      expect(described_class.money("1,780")).to eq(1780.0)
      expect(described_class.money("$ 61,200")).to eq(61_200.0)
      expect(described_class.money("-")).to be_nil
      expect(described_class.money(12.5)).to eq(12.5)
    end

    it "reads the dates QDS prints" do
      expect(described_class.date("10-Sep-26")).to eq(Date.new(2026, 9, 10))
      expect(described_class.date("2026-01-04")).to eq(Date.new(2026, 1, 4))
      expect(described_class.date("garbage")).to be_nil
    end

    it "accepts only sensible percentages" do
      expect(described_class.percent("10 %")).to eq(10.0)
      expect(described_class.percent("250")).to be_nil
    end
  end

  describe VendorManagement::PoReader::Validator do
    def po_with(lines, total: nil, currency: "USD")
      { "lines" => lines, "total_value" => total, "currency" => currency, "warnings" => [] }
    end

    it "repairs a quantity misread when quantity x unit price must equal the total" do
      po = po_with([{ "quantity" => 7.0, "unit_price" => 8250.0, "line_total" => 16_500.0 }], total: 16_500.0)
      described_class.new(po).call
      expect(po["lines"].first["quantity"]).to eq(2)
      expect(po["lines"].first["flags"].first).to match(/changed to 2/)
      expect(po["warnings"]).to be_empty
    end

    it "fills in a missing total and warns when lines and PO total disagree" do
      po = po_with([{ "quantity" => 2.0, "unit_price" => 100.0, "line_total" => nil }], total: 500.0)
      described_class.new(po).call
      expect(po["lines"].first["line_total"]).to eq(200.0)
      expect(po["warnings"].join).to match(/add up to 200.00 but the PO total is 500.00/)
    end

    it "uses the scan's printed amounts to fix a total the model calculated" do
      printed = Set.new([890.0, 1780.0, 1780.0])
      po = po_with([{ "quantity" => 3.0, "unit_price" => 890.0, "line_total" => 2670.0 }], total: 1780.0)
      described_class.new(po, ocr_numbers: printed).call
      expect(po["lines"].first["line_total"]).to eq(1780.0)
      expect(po["lines"].first["quantity"]).to eq(2)
    end

    it "hints at a skipped row when the gap is printed on the scan" do
      printed = Set.new([100.0, 54_500.0, 100.0])
      po = po_with([{ "quantity" => 1.0, "unit_price" => 100.0, "line_total" => 100.0 }], total: 54_600.0)
      described_class.new(po, ocr_numbers: printed).call
      expect(po["warnings"].join).to match(/missing 54,500.00 is printed on the scan/)
    end

    it "falls back to QAR for a currency this app does not support" do
      po = po_with([], total: 10.0, currency: "EUR")
      described_class.new(po).call
      expect(po["currency"]).to eq("QAR")
    end
  end

  describe VendorManagement::PoReader::PaymentSchedule do
    it "builds a schedule from percentages and balances the rounding" do
      rows = [10, 10, 15, 15, 15, 15, 10, 10].map { |p| { "description" => "Part #{p}", "percent" => p } }
      result = described_class.new(installments: rows, total: 105_000.0, issue_date: Date.new(2026, 5, 6), terms_text: "").call
      amounts = result["installments"].map { |r| r["amount"] }
      expect(amounts.first).to eq(10_500.0)
      expect(amounts.sum.round(2)).to eq(105_000.0)
    end

    it "turns '60 Days Credit' into one payment 60 days after the PO date" do
      result = described_class.new(installments: [], total: 360_345.0, issue_date: Date.new(2026, 9, 10), terms_text: "60 Days Credit").call
      expect(result["installments"].size).to eq(1)
      expect(result["installments"].first).to include("amount" => 360_345.0, "due_on" => "2026-11-09")
    end

    it "turns an annual plan into one payment per year" do
      result = described_class.new(installments: [], total: 3_253_798.22, issue_date: Date.new(2026, 9, 13),
                                   terms_text: "Annual Payment for 3 Years (QAR 1,084,599.41)").call
      amounts = result["installments"].map { |r| r["amount"] }
      expect(amounts).to eq([1_084_599.41, 1_084_599.41, 1_084_599.40]) # last one absorbs the rounding
      expect(amounts.sum.round(2)).to eq(3_253_798.22)
      expect(result["installments"].map { |r| r["due_on"] }).to eq(%w[2026-09-13 2027-09-13 2028-09-13])
    end
  end

  describe VendorManagement::PoReader::HeaderHeuristics do
    let(:text) do
      <<~TEXT
        === PAGE 1 ===
        QATAR DATAMATION SYSTEMS W.L.L
        10-Sep-26
        Supplier Name: GULF IT NETWORK DISTRIBUTION FZ LLC
        Purchase Order No. QDS/CMSG-335/671
        Quotation Reference No.: QDS/Thales Luna/20260618
        Total Amount in USD      360,345.00
        Special Note: Kindly activate the license 6 months from the date of the PO
        Payment Terms: Advance | 10% On Signing
        Advance [10% 1-Month After
        15% On Completion
        15% 1-Month After
        15% On Completion
        15% 1-Month After
        10% On Completion
        10% Post Go Live
        Delivery:
        End-User Details:
        End User Company Name |Council of Ministers Secretariat General Inco Terms: DDP delivery
      TEXT
    end

    it "reads the printed anchors" do
      result = described_class.new(text).call
      expect(result).to include("po_number" => "QDS/CMSG-335/671", "currency" => "USD", "total_value" => 360_345.0,
                                "supplier_name" => "GULF IT NETWORK DISTRIBUTION FZ LLC", "incoterm" => "DDP")
      expect(result["issue_date_text"]).to eq("10-Sep-26")
      expect(result["quotation_ref"]).to eq("QDS/Thales Luna/20260618")
    end

    it "finds a percentage payment schedule that adds up to 100" do
      installments = described_class.new(text).call["installments"]
      expect(installments.map { |r| r["percent"] }).to eq([10, 10, 15, 15, 15, 15, 10, 10].map(&:to_f))
    end
  end

  describe VendorManagement::PoReader::VendorMatcher do
    let(:vendors) { [VendorManagement::Vendor.new(id: 1, name: "Gulf IT Network Distribution"), VendorManagement::Vendor.new(id: 2, name: "Other Co")] }

    it "matches a supplier name that only differs by legal suffix and case" do
      match = described_class.new(vendors).match("GULF IT NETWORK DISTRIBUTION FZ LLC")
      expect(match["id"]).to eq(1)
    end

    it "does not match an unrelated supplier" do
      expect(described_class.new(vendors).match("Maison Consulting Gulf Limited")).to be_nil
    end
  end

  describe VendorManagement::PoReader::Extractor do
    let(:client) { instance_double(VendorManagement::PoReader::OllamaClient) }
    let(:text) do
      <<~TEXT
        Supplier Name: ACME LLC
        Purchase Order No. QDS/ABC-12/9
        10-Sep-26
        Part No.   Description   Qty   Unit Price   Total Price
        A-1   Widget   2   50.00   100.00
        Optional: Extras
        B-2   Gadget   1   25.00   25.00
        Total Amount in QAR   125.00
        Payment Terms: 30 Days Credit
      TEXT
    end

    it "reads rows from the model and drops duplicates it repeated" do
      allow(client).to receive(:generate_json).and_return(
        { "rows" => [["", "A-1", "Widget", 2, 50, 100], ["", "B-2", "Gadget", 1, 25, 25], ["Optional: Extras", "B-2", "Gadget", 1, 25, 25]] }
      )
      po = described_class.new(text, client:).call
      expect(po["lines"].size).to eq(2)
      expect(po["lines"].last["section"]).to eq("Optional: Extras")
      expect(po["po_number"]).to eq("QDS/ABC-12/9")
      expect(po["total_value"]).to eq(125.0)
    end

    it "does not call the model for the header when the printed anchors are enough" do
      expect(client).to receive(:generate_json).once.and_return({ "rows" => [] })
      described_class.new(text, client:).call
    end

    it "reports an unreachable model as a warning instead of failing" do
      allow(client).to receive(:generate_json).and_raise(VendorManagement::PoReader::OllamaClient::Error, "no AI")
      po = described_class.new(text, client:).call
      expect(po["warnings"].join).to match(/no AI/)
    end
  end

  describe VendorManagement::PoReader::ExcelReader do
    let(:client) { instance_double(VendorManagement::PoReader::OllamaClient) }

    def workbook(rows)
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "POs") { |sheet| rows.each { |r| sheet.add_row(r) } }
      package.to_stream.read
    end

    it "finds several POs in one table from the column titles, without needing the AI" do
      rows = [
        ["Ref", "Vendor", "Cur", "Item code", "Item", "Qty", "Rate", "Amount", "Terms"],
        ["P-1", "ACME LLC", "QAR", "A", "Widget", 2, 50, 100, "30 days credit"],
        ["P-1", "ACME LLC", "QAR", "B", "Gadget", 1, 25, 25, "30 days credit"],
        ["P-2", "Beta WLL", "USD", "C", "Service day", 3, 10, 30, "50% on order, 50% on delivery"]
      ]
      expect(client).not_to receive(:generate_json)
      result = described_class.new(workbook(rows), "x.xlsx", client:).call
      expect(result["pos"].map { |p| p["po_number"] }).to eq(%w[P-1 P-2])
      expect(result["pos"].first["lines"].map { |l| l["line_total"] }).to eq([100.0, 25.0])
      expect(result["pos"].last).to include("currency" => "USD", "supplier_name" => "Beta WLL", "payment_terms" => "50% on order, 50% on delivery")
    end

    it "reads a one-PO sheet whose header values sit above the table" do
      rows = [["Supplier:", "Solo Trading"], ["PO No:", "S-77"], [], ["Description", "Qty", "Price", "Total"], ["Pump", 1, 10, 10], ["TOTAL", nil, nil, 10]]
      expect(client).not_to receive(:generate_json)
      result = described_class.new(workbook(rows), "x.xlsx", client:).call
      expect(result["pos"].size).to eq(1)
      expect(result["pos"].first).to include("po_number" => "S-77", "supplier_name" => "Solo Trading")
      expect(result["pos"].first["lines"].map { |l| l["line_total"] }).to eq([10.0])
    end

    it "asks the AI only about titles it does not know, and maps its answer back by title text" do
      rows = [["Order Ref", "Material", "Qty Ordered", "Cost each", "Cost"], ["P-5", "Cable", 4, 5, 20]]
      allow(client).to receive(:generate_json).and_return({ "description" => "Material", "unit_price" => "Cost each", "line_total" => "Cost" })
      result = described_class.new(workbook(rows), "x.xlsx", client:).call
      line = result["pos"].first["lines"].first
      expect(result["pos"].first["po_number"]).to eq("P-5")
      expect(line).to include("description" => "Cable", "quantity" => 4.0, "unit_price" => 5.0, "line_total" => 20.0)
    end

    it "says so when titles are unknown and the AI is down" do
      rows = [["Order Ref", "Material", "Qty Ordered", "Cost each", "Cost"], ["P-5", "Cable", 4, 5, 20]]
      allow(client).to receive(:generate_json).and_raise(VendorManagement::PoReader::OllamaClient::Error, "down")
      result = described_class.new(workbook(rows), "x.xlsx", client:).call
      expect(result["warnings"].join).to match(/matched by their titles only/)
    end
  end

  describe VendorManagement::PoReader::Creator do
    let(:project) { create(:project) }
    let(:user) { create(:admin) }
    let(:import) do
      VendorManagement::PoIntake.create!(project:, user:, source_kind: "pdf", source_filename: "po.pdf",
                                         source_content_type: "application/pdf", source_data: "%PDF-1.4", status: "ready")
    end

    it "creates the vendor, PO, lines and payment schedule from the reviewed form" do
      form = { "0" => { "index" => "0", "po_number" => "QDS/X-1/1", "issue_date" => "2026-09-10", "currency" => "USD",
                        "vendor_id" => "new", "new_vendor_name" => "Brand New LLC", "payment_terms" => "60 Days Credit",
                        "lines" => { "0" => { "section" => "", "part_no" => "A", "description" => "Licence renewal", "quantity" => "2", "unit_price" => "50" },
                                     "1" => { "description" => "Skipped", "quantity" => "1", "unit_price" => "5", "skip" => "1" } },
                        "installments" => { "0" => { "description" => "Payment", "percent" => "100", "amount" => "100", "due_on" => "2026-11-09" } } } }
      result = described_class.new(import:, user:, form:).call
      expect(result.errors).to be_empty
      po = result.created.first
      expect(po.vendor.name).to eq("Brand New LLC")
      expect(po.po_line_items.count).to eq(1)
      expect(po.total_value).to eq(100)
      expect(po.po_installments.first.due_on).to eq(Date.new(2026, 11, 9))
      expect(po.quotation_file_attached?).to be(true)
    end

    it "reports a duplicate PO number without stopping the others" do
      vendor = VendorManagement::Vendor.create!(name: "Existing", status: "active")
      VendorManagement::PurchaseOrder.create!(project:, vendor:, po_number: "DUP-1", currency: "QAR")
      form = { "0" => { "index" => "0", "po_number" => "DUP-1", "vendor_id" => vendor.id.to_s },
               "1" => { "index" => "1", "po_number" => "OK-1", "vendor_id" => vendor.id.to_s } }
      result = described_class.new(import:, user:, form:).call
      expect(result.created.map(&:po_number)).to eq(["OK-1"])
      expect(result.errors.join).to match(/DUP-1/)
    end
  end
end
