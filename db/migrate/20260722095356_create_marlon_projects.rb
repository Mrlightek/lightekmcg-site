# frozen_string_literal: true
class CreateMarlonProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_projects do |t|
      t.string   :title,       null: false
      t.text     :description
      t.bigint   :client_id
      t.bigint   :owner_id
      t.bigint   :purchase_id
      t.string   :status,      null: false, default: "planning"
      t.date     :start_date
      t.date     :due_date
      t.timestamps
    end
    add_index :marlon_projects, :client_id
    add_index :marlon_projects, :owner_id
    add_index :marlon_projects, :purchase_id
    add_index :marlon_projects, :status
  end
end
