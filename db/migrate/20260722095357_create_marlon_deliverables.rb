# frozen_string_literal: true
class CreateMarlonDeliverables < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_deliverables do |t|
      t.references :project, null: false, foreign_key: { to_table: :marlon_projects }
      t.string   :name,      null: false
      t.text     :description
      t.string   :status,    null: false, default: "pending"
      t.date     :due_date
      t.datetime :completed_at
      t.timestamps
    end
    add_index :marlon_deliverables, :status
  end
end
