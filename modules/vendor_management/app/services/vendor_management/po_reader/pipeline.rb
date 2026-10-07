module VendorManagement
  module PoReader
    # Runs one PoIntake from the uploaded bytes to a reviewable result:
    #   PDF   : OCR -> AI reading -> arithmetic check -> payment schedule
    #   Excel : AI column mapping -> rows -> arithmetic check -> payment schedule
    # then matches vendors and cross-checks the O&D in the PO number against
    # the project. Nothing is saved to purchase orders here -- the user
    # reviews first (see Creator).
    class Pipeline
      PO_NUMBER_OD = %r{\A[A-Z]{2,6}/[A-Z]{2,6}-(\d+)/\d+}

      # Reading one file must not take longer than this; the slow model gets whatever time is left.
      TIME_LIMIT = 30

      def initialize(import, client: OllamaClient.new(deadline: Time.now + TIME_LIMIT))
        @import = import
        @client = client
      end

      def call
        raw = @import.source_kind == "pdf" ? read_pdf : read_excel
        @import.update_stage!("Checking the numbers")
        matcher = VendorMatcher.new
        warnings = Array(raw["warnings"])

        pos = raw["pos"].each_with_index.map { |po, i| finish(po, matcher, i, raw["ocr_numbers"]) }
        result = { "source_kind" => @import.source_kind, "pos" => pos, "warnings" => warnings, "mapping" => raw["mapping"] }
        result["ocr_text"] = raw["ocr_text"].to_s.truncate(20_000) if raw["ocr_text"]
        result
      end

      private

      def read_pdf
        @import.update_stage!("Reading the scanned pages (OCR)")
        ocr = PdfOcr.new(@import.source_data).call
        text = ocr.text
        @import.update_stage!("Reading the items table")
        parsed = TableParser.new(ocr.tsv_pages).call
        parsed = TextTableParser.new(text).call if parsed.empty? # a text PDF, or a layout the ruled-table reader does not know
        @import.update_stage!("The AI is reading the purchase order")
        po = Extractor.new(text, client: @client, parsed_lines: parsed).call
        numbers = text.scan(/\d[\d.,]*[.,]\d+/).filter_map { |s| Numbers.money(s) }.to_set
        { "pos" => [po], "ocr_text" => text, "ocr_numbers" => numbers }
      end

      def read_excel
        @import.update_stage!("The AI is looking at the spreadsheet")
        ExcelReader.new(@import.source_data, @import.source_filename, client: @client).call
      end

      def finish(po, matcher, index, ocr_numbers = nil)
        po["issue_date"] = Numbers.date(po["issue_date_text"])&.iso8601
        po["lines"] ||= []
        Validator.new(po, ocr_numbers:).call

        schedule = PaymentSchedule.new(
          installments: po["installments"], total: po["total_value"],
          issue_date: po["issue_date"] && Date.parse(po["issue_date"]), terms_text: po["payment_terms"]
        ).call
        po["installments"] = schedule["installments"]
        po["warnings"] = (po["warnings"] + schedule["warnings"]).uniq

        po["o_and_d"] = po["po_number"].to_s[PO_NUMBER_OD, 1]
        check_project(po)
        po["vendor_match"] = matcher.match(po["supplier_name"])
        po["index"] = index
        po["duplicate_in_project"] = VendorManagement::PurchaseOrder.exists?(project_id: @import.project_id, po_number: po["po_number"].to_s) if po["po_number"].present?
        po["warnings"] << "A PO numbered #{po['po_number']} already exists in this project." if po["duplicate_in_project"]
        po
      end

      def check_project(po)
        return if po["o_and_d"].blank?

        field = ProjectCustomField.find_by(name: "O&D")
        return unless field

        project_od = CustomValue.find_by(customized_type: "Project", customized_id: @import.project_id, custom_field_id: field.id)&.value.to_s.strip
        return if project_od.blank? || project_od.split(/\s*&\s*/).include?(po["o_and_d"].to_s.sub(/\A0+/, "")) || project_od.split(/\s*&\s*/).include?(po["o_and_d"])

        po["warnings"] << "The PO number points to O&D #{po['o_and_d']} but this project's O&D is #{project_od}. Make sure it belongs here."
      end
    end
  end
end
