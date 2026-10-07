module PaymentTerms
  # Daily scheduled check (registered in PaymentTerms::Engine's cron
  # block) -- unlike vendor_management's approval-chain notifications,
  # this isn't tied to a save/journal event: a payment becomes due
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

    # Recipients are resolved by these NAMED roles, not by the
    # edit_payment_terms permission grant itself -- per the user's explicit
    # choice, so this stays scoped to project leadership even if
    # edit_payment_terms is later granted to another role (e.g. Finance).
    # Both names are real, currently-assigned PMO roles (confirmed live on
    # production: Project Manager and Program Manager both cover real
    # project leads today -- Program Manager alone covers a project with no
    # Project Manager assigned at all).
    MANAGER_ROLE_NAMES = ["Project Manager", "Program Manager"].freeze

    def perform
      due_payments.find_each do |payment|
        notify_for(payment)
      end
    end

    private

    # `..Date.current` (not `...Date.current`) -- inclusive of today, so a
    # payment due TODAY notifies immediately rather than waiting until
    # tomorrow's run for it to count as "overdue".
    def due_payments
      PaymentTerms::Payment
        .live
        .joins(contract_line: :project)
        .where(projects: { active: true })
        .where(invoiced: false)
        .where.not(expected_invoice_date: nil)
        .where(expected_invoice_date: ..Date.current)
    end

    def notify_for(payment)
      project = payment.project
      return unless project

      recipients(project).each do |user|
        next if Notification.exists?(resource: payment, recipient: user, reason: :subscribed)

        notification = self.class.create_notification(user, payment)
        Notifications::MailService.new(notification).call if notification
      end
    end

    # Project/Program Managers of the project who have this notification
    # switched on -- shared with ArchiveSettledProjectsJob.
    def self.recipients_for(project)
      user_ids = Member.joins(:roles)
                        .where(project_id: project.id, roles: { name: MANAGER_ROLE_NAMES })
                        .distinct
                        .pluck(:user_id)

      NotificationSetting
        .where(payment_terms_invoice_overdue: true, user_id: user_ids)
        .includes(:user)
        .map(&:user)
    end

    def recipients(project)
      self.class.recipients_for(project)
    end

    def self.create_notification(user, payment)
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

