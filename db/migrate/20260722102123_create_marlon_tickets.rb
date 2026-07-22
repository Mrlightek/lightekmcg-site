# frozen_string_literal: true
class CreateMarlonTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_tickets do |t|
      t.string   :number,          null: false
      t.string   :category,        null: false
      t.string   :title,           null: false
      t.text     :description
      t.string   :priority,        null: false, default: "medium"
      t.integer  :urgency,         null: false, default: 5
      t.string   :status,          null: false, default: "open"
      t.bigint   :submitted_by_id
      t.string   :organization_name
      t.string   :reseller_id
      t.string   :assigned_team
      t.string   :assigned_rep
      t.jsonb    :extra_fields
      # Polymorphic link to whatever this ticket is about — a Project, a
      # Purchase, a Deliverable, or nothing (a raw standalone ticket).
      # Same doctrine as WorkItem#subject: dynamic reads, one column pair
      # instead of a foreign key per possible thing a ticket could relate to.
      t.string   :related_type
      t.bigint   :related_id
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :marlon_tickets, :number, unique: true
    add_index :marlon_tickets, :status
    add_index :marlon_tickets, :category
    add_index :marlon_tickets, %i[related_type related_id]
    add_index :marlon_tickets, :submitted_by_id
  end
end
