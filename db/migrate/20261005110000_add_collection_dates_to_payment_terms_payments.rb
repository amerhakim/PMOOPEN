class AddCollectionDatesToPaymentTermsPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_terms_payments, :expected_collection_date, :date
    add_column :payment_terms_payments, :actual_collection_date, :date
  end
end
