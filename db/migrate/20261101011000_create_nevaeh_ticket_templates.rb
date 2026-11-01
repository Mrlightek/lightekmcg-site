# frozen_string_literal: true
class CreateNevaehTicketTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_ticket_templates do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :sections, null: false, default: []
      t.timestamps
    end
  end
end
