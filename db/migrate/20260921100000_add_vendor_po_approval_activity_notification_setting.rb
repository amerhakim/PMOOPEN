class AddVendorPoApprovalActivityNotificationSetting < ActiveRecord::Migration[8.1]
  def change
    # Default true so approvers/submitters are notified out of the box,
    # matching the business requirement (role-based, not opt-in) --
    # see the ADDENDUM (2026-09-21) plan section and
    # openproject_notification_system memory for the full research
    # behind why this couldn't be role-scoped any other way without
    # editing NotificationSetting::CreateFromModelService itself.
    add_column :notification_settings, :vendor_po_approval_activity, :boolean, default: true, null: false
  end
end
