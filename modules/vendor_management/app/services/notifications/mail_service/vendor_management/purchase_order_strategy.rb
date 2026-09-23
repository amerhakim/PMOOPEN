module Notifications::MailService::VendorManagement
  # Same nested-namespace requirement as
  # Notifications::CreateFromModelService::VendorManagement::PurchaseOrderStrategy
  # -- MailService#strategy_model uses the journal's journable_type STRING
  # ("VendorManagement::PurchaseOrder"), so the resolved constant path is
  # Notifications::MailService::VendorManagement::PurchaseOrderStrategy.
  module PurchaseOrderStrategy
    class << self
      def send_mail(notification)
        po = notification.resource
        return unless po

        # Branch on the journal's OWN snapshot status (frozen at the
        # moment this notification was created), not po.status live --
        # by the time this actually sends (after the journal aggregation
        # delay), the PO may have moved on further, and the email should
        # still describe the event that triggered it, not whatever the
        # PO's current state happens to be by then.
        case notification.journal&.data&.status
        when "pending_approval"
          VendorManagementMailer.po_needs_approval(notification.recipient, po).deliver_later
        when "approved", "draft"
          VendorManagementMailer.po_decision_made(notification.recipient, po).deliver_later
        end
      end
    end
  end
end
