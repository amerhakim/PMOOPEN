class Notifications::CreateFromModelService
  module VendorManagement
    # Resolved by Notifications::CreateFromModelService#strategy via
    # "#{self.class}::#{resource.class}Strategy".constantize -- for a
    # namespaced journable class like VendorManagement::PurchaseOrder
    # this genuinely needs a matching NESTED module here
    # (Notifications::CreateFromModelService::VendorManagement::PurchaseOrderStrategy),
    # not a flat "...::PurchaseOrderStrategy" the way modules/documents'
    # own (unnamespaced) DocumentStrategy gets away with. Confirmed live
    # via rails runner before writing this file -- see
    # openproject_notification_system memory for the full research.
    class PurchaseOrderStrategy
      def self.reasons
        %i[subscribed]
      end

      # Tighter gate while a decision is pending (only real approvers
      # count), looser once a decision has been made (the submitter just
      # needs to be able to see the PO at all, not approve it).
      def self.permission(journal, _reason)
        journal.data.status == "pending_approval" ? :manage_vendor_management_approvals : :view_vendor_management
      end

      def self.supports_ian?(_reason)
        true
      end

      def self.supports_mail_digest?(_reason)
        false
      end

      def self.supports_mail?(_reason)
        true
      end

      # Candidate recipients only -- CreateFromModelService additionally
      # intersects this with whoever actually has `permission` above in
      # the project (see settings_for_allowed_users), so it's safe to
      # return a broad "every project member" scope for the
      # approval-needed case and let that intersection do the real
      # narrowing down to real approvers.
      #
      # Known gap, not covered by this phase: only PurchaseOrder itself
      # is journaled (not PoApprovalStep), and PurchaseOrder#status stays
      # "pending_approval" for the WHOLE multi-step chain -- only the
      # first submit and the final decision produce a PurchaseOrder
      # journal. A mid-chain step approval (moving from step 1's
      # approver to step 2's) does not yet notify anyone; would need
      # PoApprovalStep journaling to close, deferred to a later phase.
      def self.subscribed_users(journal)
        # Deliberately NOT guarding on journal.initial? -- a PO created
        # and submitted for approval within the same aggregation window
        # (very plausible: fill the form, save, click submit right
        # after) genuinely produces an "initial" journal whose snapshot
        # already carries status "pending_approval". The "draft" branch
        # below is already safe for a bare, never-submitted creation --
        # submitted_by is nil at that point, so it resolves to User.none
        # on its own without needing an initial? check at all.
        po = journal.journable
        case journal.data.status
        when "pending_approval"
          po.next_pending_step ? po.project.users : User.none
        when "approved", "draft"
          po.submitted_by ? User.where(id: po.submitted_by_id) : User.none
        else
          User.none
        end
      end

      def self.subscribed_notification_reason(_journal)
        NotificationSetting::VENDOR_PO_APPROVAL_ACTIVITY
      end

      def self.project(journal)
        journal.journable.project
      end

      def self.user(journal)
        journal.user
      end
    end
  end
end
