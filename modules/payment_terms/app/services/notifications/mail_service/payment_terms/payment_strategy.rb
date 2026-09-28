module Notifications::MailService::PaymentTerms
  # Same nested-namespace requirement as
  # Notifications::MailService::VendorManagement::PurchaseOrderStrategy
  # (see openproject_notification_system memory) -- for a
  # notification with no journal, MailService#strategy_model falls back
  # to resource&.class, i.e. PaymentTerms::Payment, so the resolved
  # constant path is Notifications::MailService::PaymentTerms::PaymentStrategy.
  module PaymentStrategy
    class << self
      def send_mail(notification)
        payment = notification.resource
        return unless payment

        PaymentTermsMailer.invoice_overdue(notification.recipient, payment).deliver_later
      end
    end
  end
end
