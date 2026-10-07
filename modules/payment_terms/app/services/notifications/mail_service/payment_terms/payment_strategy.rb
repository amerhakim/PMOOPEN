module Notifications::MailService::PaymentTerms
  # Same nested-namespace requirement as
  # Notifications::MailService::VendorManagement::PurchaseOrderStrategy
  # (see openproject_notification_system memory) -- for a
  # notification with no journal, MailService#strategy_model falls back
  # to resource&.class, i.e. PaymentTerms::Payment, so the resolved
  # constant path is Notifications::MailService::PaymentTerms::PaymentStrategy.
  module PaymentStrategy
    class << self
      # Two kinds of notification hang off a payment: "invoice overdue"
      # (project still active) and "project archived" (sent right after
      # ArchiveSettledProjectsJob archives the project). The overdue job
      # never notifies for archived projects, so the project's state alone
      # tells them apart.
      def send_mail(notification)
        payment = notification.resource
        return unless payment

        mail =
          if payment.project.active?
            PaymentTermsMailer.invoice_overdue(notification.recipient, payment)
          else
            PaymentTermsMailer.project_archived(notification.recipient, payment)
          end
        mail.deliver_later
      end
    end
  end
end
