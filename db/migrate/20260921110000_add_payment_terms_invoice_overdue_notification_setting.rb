class AddPaymentTermsInvoiceOverdueNotificationSetting < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_settings, :payment_terms_invoice_overdue, :boolean, default: true, null: false
  end
end
