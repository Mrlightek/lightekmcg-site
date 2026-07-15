# frozen_string_literal: true

class CreateMarlonGeneratedArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :marlon_generated_artifacts do |t|
      t.string :blueprint_key, null: false
      t.string :artifact_type, null: false
      t.string :path, null: false
      t.string :checksum
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :marlon_generated_artifacts,
      [:blueprint_key, :path], unique: true,
      name: "idx_marlon_generated_artifacts_unique"
  end
end
