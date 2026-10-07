module PaymentTerms
  module Payments
    class RowComponent < ::RowComponent
      def payment
        model
      end

      # Extra data-* attributes read by the shared client-side filter bar
      # (see _contract_line_card.html.erb / index.html.erb) so it can
      # show/hide rows across every card on the page without a server
      # round-trip. The row's own visible text already covers the
      # description search.
      def row_data
        {
          "expected-iso" => payment.expected_invoice_date&.iso8601,
          "invoice-iso" => payment.invoice_date&.iso8601,
          invoiced: payment.invoiced?,
          collected: payment.collected?,
          cancelled: payment.cancelled?
        }
      end

      # Folds the old standalone Milestone/Comments columns into a small
      # info icon next to the description, only when there's something to
      # show -- the redesign's whole point was fewer columns.
      def description
        text = content_tag(:span, payment.description, class: "payment-terms-description-text")
        text = safe_join([content_tag(:s, text), content_tag(:span, I18n.t("payment_terms.index.cancelled_badge"), class: "payment-terms-cancelled-badge")]) if payment.cancelled?
        return text if description_info.blank?

        icon = content_tag(:span, "i", class: "payment-terms-info-icon", title: description_info, "aria-label": description_info)
        safe_join([text, icon], " ")
      end

      def value
        return unless payment.value

        formatted = helpers.payment_terms_money(payment.value, payment.currency)
        payment.cancelled? ? content_tag(:s, formatted) : formatted
      end

      def invoiced
        status_dot(payment.invoiced?, on_color: "#9A6B1A")
      end

      def expected_invoice_date
        helpers.format_date(payment.expected_invoice_date)
      end

      def collected
        status_dot(payment.collected?, on_color: "#1E6B45")
      end

      def expected_collection_date
        helpers.format_date(payment.expected_collection_date)
      end

      def actual_collection_date
        helpers.format_date(payment.actual_collection_date)
      end

      def invoice_number
        payment.invoice_number
      end

      def invoice_date
        helpers.format_date(payment.invoice_date)
      end

      def button_links
        return [] unless table.can_edit

        [edit_link, delete_link]
      end

      def edit_link
        link_to(
          helpers.op_icon("icon icon-edit"),
          helpers.projects_edit_payment_terms_payment_path(payment.project, payment),
          title: I18n.t(:button_edit)
        )
      end

      def delete_link
        link_to(
          helpers.op_icon("icon icon-delete"),
          helpers.projects_payment_terms_payment_path(payment.project, payment),
          data: { turbo_method: :delete, turbo_confirm: I18n.t(:text_are_you_sure) },
          title: I18n.t(:button_delete)
        )
      end

      private

      def description_info
        @description_info ||= [payment.milestone&.subject, payment.comments].map(&:presence).compact.join(" — ")
      end

      def status_dot(active, on_color:)
        color = active ? on_color : "#9AA3AD"
        label = active ? I18n.t(:general_text_yes) : I18n.t(:general_text_no)
        content_tag(:span, "", class: "payment-terms-status-dot", style: "background-color:#{color};", title: label, "aria-label": label)
      end
    end
  end
end


