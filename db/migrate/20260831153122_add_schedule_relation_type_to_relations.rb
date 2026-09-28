class AddScheduleRelationTypeToRelations < ActiveRecord::Migration[8.1]
  def change
    add_column :relations, :schedule_relation_type, :string, null: true, default: nil

    # nil means "FS" (Finish-to-Start), the only behaviour that existed before
    # this column was added, so no backfill is needed for existing rows.
  end
end
