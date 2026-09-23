class PaymentTermsMailer < UserMailer
  def invoice_overdue(user, payment)
    @payment = payment

    open_project_headers "Project" => @payment.project.identifier,
                         "Type" => "PaymentTerms::Payment"

    send_localized_mail(user) do
      "[#{@payment.project.name}] #{t('payment_terms.notifications.invoice_overdue_subject', description: @payment.description)}"
    end
  end
end
