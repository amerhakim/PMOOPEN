class CreateMsProjectImports < ActiveRecord::Migration[8.1]
  def change
    create_table :ms_project_imports do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :original_filename, null: false
      t.integer :tasks_created_count, default: 0, null: false
      t.integer :relations_created_count, default: 0, null: false
      t.text :error_message

      t.timestamps
    end
  end
end
