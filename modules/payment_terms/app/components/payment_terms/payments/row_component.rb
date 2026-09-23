module PaymentTerms
  module Payments
    class RowComponent < ::RowComponent
      def payment
        model
      end

      def sn
        table.rows.to_a.index(payment) + 1
      end

      def description
        payment.description
      end

      def percent
        payment.percent
      end

      def value
        return unless payment.value

        helpers.number_to_currency(payment.value, unit: "QAR ", format: "%u%n")
      end

      def milestone
        return unless payment.milestone

        link_to payment.milestone.subject, helpers.work_package_path(payment.milestone)
      end

      def invoiced
        payment.invoiced? ? I18n.t(:general_text_yes) : I18n.t(:general_text_no)
      end

      def expected_invoice_date
        helpers.format_date(payment.expected_invoice_date)
      end

      def collected
        payment.collected? ? I18n.t(:general_text_yes) : I18n.t(:general_text_no)
      end

      def invoice_number
        payment.invoice_number
      end

      def invoice_date
        helpers.format_date(payment.invoice_date)
      end

      def comments
        payment.comments
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
    end
  end
end
