class AddCurrencyAndCancelledToPaymentTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_terms_contract_lines, :currency, :string, null: false, default: "QAR"
    add_column :payment_terms_payments, :cancelled, :boolean, null: false, default: false
    add_index :payment_terms_payments, :cancelled
  end
end
