# frozen_string_literal: true
class CreateMarlonTimesheets < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_timesheets do |t|
      t.references :project, null: false, foreign_key: { to_table: :marlon_projects }
      t.bigint   :user_id,   null: false
      t.decimal  :hours,     null: false, precision: 6, scale: 2
      t.date     :worked_on, null: false
      t.text     :notes
      t.timestamps
    end
    add_index :marlon_timesheets, :user_id
    add_index :marlon_timesheets, :worked_on
  end
end
