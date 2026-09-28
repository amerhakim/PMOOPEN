class CreateCustomBrandings < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_brandings do |t|
      t.string :logo
      t.string :header_bg_color
      t.string :main_menu_bg_color
      t.string :main_menu_bg_selected_background
      t.string :accent_color
      t.string :primary_button_color
      t.timestamps
    end
  end
end
