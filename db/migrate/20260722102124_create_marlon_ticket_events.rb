# frozen_string_literal: true
class CreateMarlonTicketEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_ticket_events do |t|
      t.references :ticket, null: false, foreign_key: { to_table: :marlon_tickets }
      t.bigint   :actor_id
      t.string   :action,   null: false
      t.text     :detail
      t.timestamps
    end
  end
end
