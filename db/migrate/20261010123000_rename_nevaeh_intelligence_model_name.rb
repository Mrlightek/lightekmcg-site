# frozen_string_literal: true

class RenameNevaehIntelligenceModelName < ActiveRecord::Migration[8.0]
  def change
    rename_column :nevaeh_intelligences, :model_name, :target_model
  end
end
