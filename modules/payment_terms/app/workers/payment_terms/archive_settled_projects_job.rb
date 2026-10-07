module PaymentTerms
  # Daily: a project that is Finished and whose every live (not cancelled)
  # payment has been collected is archived automatically, and its
  # Project/Program Managers are told. Archiving takes it off the
  # dashboard cards and the live Project Invoices report; it stays
  # reversible (Unarchive) and its totals are still counted.
  class ArchiveSettledProjectsJob < ApplicationJob
    queue_with_priority :notification

    def perform
      settled_projects.each do |project|
        result = Projects::ArchiveService.new(user: User.system, model: project).call
        notify_managers(project) if result.success?
      end
    end

    private

    def settled_projects
      with_payments = PaymentTerms::ContractLine.select(:project_id).distinct

      Project.where(active: true, status_code: Project.status_codes[:finished], id: with_payments)
             .select { |project| settled?(project) && project.active_subprojects.none? }
    end

    def settled?(project)
      live = PaymentTerms::Payment.live.joins(:contract_line).where(payment_terms_contract_lines: { project_id: project.id })
      live.exists? && !live.where(collected: false).exists?
    end

    # The notification hangs off the project's last payment (a
    # notification's resource must answer #project, which Payment does) and
    # PaymentStrategy picks the "archived" email because the project is
    # archived by now.
    def notify_managers(project)
      payment = PaymentTerms::Payment.live.joins(:contract_line)
                                     .where(payment_terms_contract_lines: { project_id: project.id }).order(:id).last
      return unless payment

      CreateInvoiceOverdueNotificationsJob.recipients_for(project).each do |user|
        notification = CreateInvoiceOverdueNotificationsJob.create_notification(user, payment)
        Notifications::MailService.new(notification).call if notification
      end
    end
  end
end
