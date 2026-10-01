# frozen_string_literal: true

class AddEventTypesToNevaehCapabilities < ActiveRecord::Migration[8.0]
  def change
    add_column :nevaeh_capabilities,
               :event_types,
               :jsonb,
               null: false,
               default: []

    add_index :nevaeh_capabilities,
              :event_types,
              using: :gin
  end
end
