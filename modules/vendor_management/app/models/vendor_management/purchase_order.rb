module VendorManagement
  # One PO within a project (REQ-PO-01: always exactly one project, one
  # vendor). `po_number` is auto-generated but editable (per the BRD);
  # `total_value` is hand-entered only while the PO has no line items yet
  # (the create/edit form exposes it then) -- the moment a real line item
  # exists, PoLineItem owns the recompute and pushes it up on every save
  # (see PoLineItem#recompute_purchase_order_total), overriding whatever
  # was typed directly.
  class PurchaseOrder < ApplicationRecord
    self.table_name = "vendor_management_purchase_orders"

    STATUSES = %w[draft pending_approval approved active closed cancelled].freeze
    CURRENCIES = %w[QAR SAR OMR USD].freeze
    DELIVERY_STATUSES = %w[not_delivered partially_delivered delivered].freeze
    PAYMENT_STATUSES = %w[not_invoiced partially_paid paid].freeze

    belongs_to :project
    belongs_to :vendor, class_name: "VendorManagement::Vendor"
    belongs_to :submitted_by, class_name: "User", optional: true
    has_many :po_line_items,
             class_name: "VendorManagement::PoLineItem",
             foreign_key: "purchase_order_id",
             dependent: :destroy,
             inverse_of: :purchase_order
    has_many :po_payments,
             -> { order(:paid_on) },
             class_name: "VendorManagement::PoPayment",
             foreign_key: "purchase_order_id",
             dependent: :destroy,
             inverse_of: :purchase_order
    has_many :po_approval_steps,
             -> { order(:sequence) },
             class_name: "VendorManagement::PoApprovalStep",
             foreign_key: "purchase_order_id",
             dependent: :destroy,
             inverse_of: :purchase_order

    before_validation :assign_po_number, on: :create

    validates :vendor, presence: true
    validates :po_number, presence: true, uniqueness: { scope: :project_id }
    validates :currency, inclusion: { in: CURRENCIES }
    validates :status, inclusion: { in: STATUSES }
    validates :delivery_status_qds, inclusion: { in: DELIVERY_STATUSES }
    validates :delivery_status_customer, inclusion: { in: DELIVERY_STATUSES }

    # Phase 1 of the notification work (see the 2026-09-21 plan addendum
    # and openproject_vendor_management_feature memory): bare journaling
    # only, tracking just "status" for now. No Strategy class exists
    # yet, so this creates real Journal rows but deliberately triggers
    # zero notifications until Phase 2 adds one.
    acts_as_journalized
    register_journal_formatted_fields "status", formatter_key: :plaintext

    # Keeps Remaining in PO / Payment Status correct for a PO whose
    # total_value was just hand-entered (no line items yet) -- the
    # line-item-driven path (recompute_total_value!) uses update_column,
    # which skips callbacks entirely, so this never double-fires there.
    after_save :recompute_payment_totals!, if: :saved_change_to_total_value?

    def recompute_total_value!
      update_column(:total_value, po_line_items.sum(:line_total))
      recompute_payment_totals!
    end

    # Total paid is a cached sum (not computed on read) so the purchase
    # orders list can sort/filter on it via plain SQL, same reasoning as
    # total_value's own caching.
    def recompute_payment_totals!
      paid = po_payments.sum(:amount)
      update_columns(total_paid: paid, remaining_in_po: (total_value.to_f - paid.to_f).round(2))
    end

    # Not a stored column -- always cheap to derive from the two cached
    # columns above, and status names never need to independently drift
    # out of sync with the amounts they describe.
    def payment_status
      return "not_invoiced" if total_paid.to_f.zero?
      return "paid" if remaining_in_po.to_f <= 0

      "partially_paid"
    end

    # Recomputes the PO-level Delivery QDS / Delivery to Customer status
    # from its line items' own per-line checkboxes: all lines checked ->
    # "delivered", none checked -> "not_delivered", otherwise
    # "partially_delivered". Called whenever a line item's delivery
    # checkboxes (or the item itself) change. Deliberately independent of
    # the approval workflow below -- per the user's own instruction,
    # delivery tracking applies once the PO exists, not gated on approval.
    def recompute_delivery_status!
      items = po_line_items.to_a
      update_columns(
        delivery_status_qds: aggregate_delivery_status(items, :delivered_to_qds?),
        delivery_status_customer: aggregate_delivery_status(items, :delivered_to_customer?)
      )
    end

    # A single manually-uploaded supporting document per PO (e.g. the
    # vendor's quotation), stored directly as bytes on this record.
    # Deliberately not Rails ActiveStorage (not installed on this
    # instance -- no active_storage_* tables) nor core's own
    # acts_as_attachable (built for a multi-file gallery with its own
    # permission-option wiring, more than a single manual upload needs)
    # -- a plain binary column is the simplest thing that actually works
    # here.
    def quotation_file=(uploaded)
      return if uploaded.blank?

      self.quotation_file_filename = uploaded.original_filename
      self.quotation_file_content_type = uploaded.content_type
      self.quotation_file_data = uploaded.read
    end

    def quotation_file_attached?
      quotation_file_data.present?
    end

    def remove_quotation_file!
      update_columns(quotation_file_filename: nil, quotation_file_content_type: nil, quotation_file_data: nil)
    end

    # Snapshots the applicable template's steps (project-specific if one
    # exists, else the company-wide default) onto this PO and moves it
    # into pending_approval. Returns false without changing anything if
    # no template with at least one step exists yet -- the user has to
    # configure the approval chain first. The chain itself is company-wide
    # config, not tied to any one project (confirmed with the user).
    def submit_for_approval!
      template = ApprovalChainTemplate.default_for(project)
      return false if template.nil? || template.approval_step_definitions.empty?

      transaction do
        template.approval_step_definitions.order(:sequence).each do |step_def|
          po_approval_steps.create!(sequence: step_def.sequence, approver_title: step_def.approver_title, status: "pending")
        end
        update!(status: "pending_approval", submitted_by: User.current)
      end
      true
    end

    # Only the lowest-sequence pending step is actionable -- a real
    # sequential chain (Logistics Coordinator before Director before GM,
    # per the BRD's own example), not a free-for-all.
    def next_pending_step
      po_approval_steps.find_by(status: "pending")
    end

    def approve_step!(step, approver_name)
      return false unless step == next_pending_step

      transaction do
        step.update!(status: "approved", approver_name:, signed_at: Time.current)
        update!(status: "approved") if po_approval_steps.reload.all? { |s| s.status == "approved" }
      end
      true
    end

    def reject_step!(step, approver_name)
      return false unless step == next_pending_step

      transaction do
        step.update!(status: "rejected", approver_name:, signed_at: Time.current)
        update!(status: "draft")
      end
      true
    end

    private

    def aggregate_delivery_status(items, predicate)
      return "not_delivered" if items.empty?
      return "delivered" if items.all?(&predicate)
      return "not_delivered" if items.none?(&predicate)

      "partially_delivered"
    end

    # Simple default sequence -- "PO-<PROJECT IDENTIFIER>-0001" -- since
    # the BRD's own reference format (QDS/CMSG-335/682) is specific to an
    # external numbering scheme this instance doesn't otherwise track.
    # The field stays editable so a real PO number can always replace it.
    def assign_po_number
      return if po_number.present?

      next_seq = PurchaseOrder.where(project_id: project_id).count + 1
      self.po_number = format("PO-%<identifier>s-%<seq>04d", identifier: project.identifier.upcase, seq: next_seq)
    end
  end
end

