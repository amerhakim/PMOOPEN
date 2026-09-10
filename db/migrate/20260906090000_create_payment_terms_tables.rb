class CreatePaymentTermsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_terms_contract_lines do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :component_value, precision: 15, scale: 2

      t.timestamps
    end

    create_table :payment_terms_payments do |t|
      t.references :contract_line, null: false, foreign_key: { to_table: :payment_terms_contract_lines }
      t.references :milestone, foreign_key: { to_table: :work_packages }
      t.text :description, null: false
      t.decimal :percent, precision: 5, scale: 2
      t.decimal :value, precision: 15, scale: 2
      t.boolean :invoiced, null: false, default: false
      t.date :expected_invoice_date
      t.boolean :collected, null: false, default: false
      t.string :invoice_number
      t.date :invoice_date
      t.text :comments

      t.timestamps
    end
  end
end
