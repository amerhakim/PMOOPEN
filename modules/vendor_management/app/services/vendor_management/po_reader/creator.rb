module VendorManagement
  module PoReader
    # Turns the reviewed form (what the user confirmed or corrected) into real
    # vendors, purchase orders, line items and payment installments. Each PO
    # is saved on its own, so one bad PO does not block the others.
    class Creator
      Result = Struct.new(:created, :errors, keyword_init: true)

      KEYWORDS = {
        "software_subscription" => /subscription|support|maintenance|renewal|sla|annual/i,
        "software_license" => /licen[sc]e|software|cloud|virtual/i,
        "service" => /service|training|implementation|installation|consult|professional|PS\b/i
      }.freeze

      def initialize(import:, user:, form:)
        @import = import
        @user = user
        @form = form || {}
      end

      def call
        created = []
        errors = []

        @form.values.sort_by { |po| po["index"].to_i }.each do |po_form|
          next if po_form["skip"].to_s == "1"

          label = po_form["po_number"].presence || "PO ##{po_form['index'].to_i + 1}"
          begin
            ActiveRecord::Base.transaction { created << create_po(po_form) }
          rescue ActiveRecord::RecordInvalid => e
            errors << "#{label}: #{e.record.errors.full_messages.to_sentence}"
          end
        end

        Result.new(created:, errors:)
      end

      private

      def create_po(f)
        vendor = vendor_for(f)
        lines = line_rows(f)

        po = VendorManagement::PurchaseOrder.new(
          project: @import.project, vendor:, po_number: f["po_number"].to_s.strip,
          issue_date: Numbers.date(f["issue_date"]), currency: f["currency"].presence || "QAR",
          quotation_ref_no: f["quotation_ref"].presence, order_description: f["order_description"].presence,
          payment_terms: f["payment_terms"].presence, special_note: f["special_note"].presence,
          incoterm: f["incoterm"].presence, delivery_address: f["delivery_address"].presence,
          end_user_name: f["end_user_name"].presence, o_and_d: f["o_and_d"].presence,
          is_non_cancellable: f["special_note"].to_s.match?(/non[-\s]?cancel+able/i),
          discount: [Numbers.money(f["discount"]).to_f.abs, 0].max,
          total_value: lines.empty? ? Numbers.money(f["total_value"]).to_f : 0
        )
        attach_source(po)
        po.save!

        lines.each do |l|
          po.po_line_items.create!(
            part_no: l[:part_no], description: l[:description], item_type: item_type(l),
            quantity: l[:quantity], unit_price: l[:unit_price], section_label: l[:section]
          )
        end
        installment_rows(f).each_with_index do |row, i|
          po.po_installments.create!(position: i, description: row[:description], percent: row[:percent],
                                     amount: row[:amount], due_on: row[:due_on])
        end
        po
      end

      def vendor_for(f)
        if f["vendor_id"].to_s == "new"
          name = f["new_vendor_name"].to_s.strip
          raise_invalid("Vendor name is required.") if name.blank?
          VendorManagement::Vendor.where("LOWER(name) = ?", name.downcase).first ||
            VendorManagement::Vendor.create!(name:, status: "active")
        else
          VendorManagement::Vendor.find_by(id: f["vendor_id"]) || raise_invalid("Choose a vendor.")
        end
      end

      def raise_invalid(message)
        record = VendorManagement::PurchaseOrder.new
        record.errors.add(:base, message)
        raise ActiveRecord::RecordInvalid, record
      end

      def attach_source(po)
        return unless @import.source_kind == "pdf"

        po.quotation_file_filename = @import.source_filename
        po.quotation_file_content_type = @import.source_content_type
        po.quotation_file_data = @import.source_data
      end

      def line_rows(f)
        (f["lines"] || {}).values.reject { |l| l["skip"].to_s == "1" }.filter_map do |l|
          description = l["description"].to_s.strip
          next if description.blank?

          quantity = Numbers.parse(l["quantity"])
          { part_no: l["part_no"].presence, description:, section: l["section"].presence,
            quantity: quantity&.positive? ? quantity : 1, unit_price: [Numbers.money(l["unit_price"]).to_f, 0].max }
        end
      end

      def installment_rows(f)
        (f["installments"] || {}).values.reject { |r| r["skip"].to_s == "1" }.filter_map do |r|
          amount = Numbers.money(r["amount"])
          next if amount.nil?

          { description: r["description"].presence || "Payment", percent: Numbers.parse(r["percent"]),
            amount:, due_on: Numbers.date(r["due_on"]) }
        end
      end

      def item_type(line)
        text = "#{line[:description]} #{line[:section]}"
        KEYWORDS.find { |_type, regex| text.match?(regex) }&.first || "hardware"
      end
    end
  end
end
