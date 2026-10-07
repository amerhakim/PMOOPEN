require_relative "../../../spec_helper"

RSpec.describe "Reading a PO that is not on the QDS template (text layer)" do
  let(:quote_text) do
    <<~TEXT
      ACME Quote Number: 00441548
      Quote Created Date: 2/9/2026
      Currency: QAR
      Payment Term: 30 days

      Customer     Some Customer Company                         Issued By:     Acme Trading LLC
      Name:

                                       Parent      Contract          Billing
       Product Number   Description                                                     Start Date      End Date       Quantity
                                       SKU         Number            Frequency
                                                                                        August 24,      August 23,
        VCF-CLD-A       Cloud Foundation                             Annual                                          912.00
                                                                                        2026            2029

                        Site Recovery                                                   August 24,      August 23,
        VCF-SRM                                                      Annual                                          100.00
                        Manager                                                         2026            2029

                                                                                                      Total Price : 3,253,798.22
    TEXT
  end

  it "finds the header facts by their labels" do
    header = VendorManagement::PoReader::GenericHeader.new(quote_text).call
    expect(header).to include("po_number" => "00441548", "issue_date_text" => "2/9/2026", "currency" => "QAR",
                              "supplier_name" => "Acme Trading LLC", "end_user_name" => "Some Customer Company",
                              "payment_terms" => "30 days", "total_value" => 3_253_798.22)
  end

  it "reads the items table from the text, including wrapped descriptions" do
    lines = VendorManagement::PoReader::TextTableParser.new(quote_text).call
    expect(lines.map { |l| [l["part_no"], l["description"], l["quantity"]] }).to eq(
      [["VCF-CLD-A", "Cloud Foundation", 912.0], ["VCF-SRM", "Site Recovery Manager", 100.0]]
    )
  end

  it "reads quantity, unit price and total by the order of the numbers" do
    text = <<~TEXT
      S.No   Part No     Description              Qty     Unit Price      Total Price
      1      AB-100-X    Firewall appliance        2       1,458.00        2,916.00
      2      AB-200-Y    Support, 1 year           3       1,417.50        4,252.50
                                                         Total Amount in USD 7,168.50
    TEXT
    lines = VendorManagement::PoReader::TextTableParser.new(text).call
    expect(lines.map { |l| [l["part_no"], l["quantity"], l["unit_price"], l["line_total"]] }).to eq(
      [["AB-100-X", 2.0, 1458.0, 2916.0], ["AB-200-Y", 3.0, 1417.5, 4252.5]]
    )
  end

  it "handles currency prefixes, wrapped product codes and a negative discount line" do
    text = <<~TEXT
      SN ProductName       Quantity   Description                    Notes     Unit price        Total Price
      1   SFP-PLUS-SR-      16        SFP-PLUS-SR-XCVR                           QAR 658.95        QAR 10,543.20
          XCVR                        Ixia SFP+ transceiver
      2   Discount - Ixia    1        Discount - Ixia                            QAR -500.00       QAR -500.00
                                      One Time Discount
                                                                                 Total        QAR 10,043.20
    TEXT
    lines = VendorManagement::PoReader::TextTableParser.new(text).call
    expect(lines.map { |l| [l["part_no"], l["description"], l["quantity"], l["unit_price"], l["line_total"]] }).to eq(
      [["SFP-PLUS-SR-XCVR", "Ixia SFP+ transceiver", 16.0, 658.95, 10_543.2],
       ["Discount - Ixia", "One Time Discount", 1.0, -500.0, -500.0]]
    )
  end

  it "finds a quote number written as 'Quote: #ABC123'" do
    header = VendorManagement::PoReader::GenericHeader.new("Quotation\nQuote: #SLQ154094\nDate: 06/05/2026\n").call
    expect(header).to include("po_number" => "SLQ154094", "issue_date_text" => "06/05/2026")
  end

  it "reads a two-digit year as 20xx" do
    expect(VendorManagement::PoReader::Numbers.date("25/08/26")).to eq(Date.new(2026, 8, 25))
  end
end
