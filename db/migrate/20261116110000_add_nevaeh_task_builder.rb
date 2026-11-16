# frozen_string_literal: true
class AddNevaehTaskBuilder < ActiveRecord::Migration[8.0]
  def change
    add_column :nevaeh_language_bindings, :builder_spec, :jsonb, null: false, default: {}
    add_column :nevaeh_language_bindings, :builder_verification, :jsonb, null: false, default: {}
  end
end
