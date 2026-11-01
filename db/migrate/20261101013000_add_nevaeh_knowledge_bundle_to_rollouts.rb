# frozen_string_literal: true
class AddNevaehKnowledgeBundleToRollouts < ActiveRecord::Migration[8.0]
  def change
    add_column :gatekeeper_rollouts, :nevaeh_lesson_bundle, :jsonb, null: false, default: {}
  end
end
