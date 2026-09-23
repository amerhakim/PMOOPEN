module PaymentTerms
  # Daily scheduled check (registered in PaymentTerms::Engine's cron
  # block) -- unlike vendor_management's approval-chain notifications,
  # this isn't tied to a save/journal event: a payment becomes overdue
  # purely by the calendar catching up to it, so it needs its own
  # recurring job rather than a Strategy hooked off acts_as_journalized.
  # See openproject_notification_system memory for the full research
  # (in particular: Notification does NOT require a journal in general --
  # only Notifications::CreateFromModelService's journal-diff flow does;
  # the lower-level Notifications::CreateService, used here directly,
  # works fine with journal: nil, exactly like core's own
  # Notifications::CreateDateAlertsNotificationsJob::Service).
  class CreateInvoiceOverdueNotificationsJob < ApplicationJob
    queue_with_priority :notification

    def perform
      overdue_payments.find_each do |payment|
        notify_for(payment)
      end
    end

    private

    def overdue_payments
      PaymentTerms::Payment
        .where(invoiced: false)
        .where.not(expected_invoice_date: nil)
        .where(expected_invoice_date: ...Date.current)
    end

    def notify_for(payment)
      project = payment.project
      return unless project

      recipients(project).each do |user|
        next if Notification.exists?(resource: payment, recipient: user, reason: :subscribed)

        notification = create_notification(user, payment)
        Notifications::MailService.new(notification).call if notification
      end
    end

    def recipients(project)
      candidates = User.allowed(:edit_payment_terms, project)
      NotificationSetting
        .where(payment_terms_invoice_overdue: true, user: candidates)
        .includes(:user)
        .map(&:user)
    end

    def create_notification(user, payment)
      result = Notifications::CreateService
               .new(user: User.system)
               .call(
                 recipient_id: user.id,
                 resource: payment,
                 reason: :subscribed,
                 read_ian: false,
                 mail_alert_sent: false
               )
      result.success? ? result.result : nil
    end
  end
end
