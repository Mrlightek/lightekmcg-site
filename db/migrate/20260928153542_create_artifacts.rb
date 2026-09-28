class CreateArtifacts < ActiveRecord::Migration[8.0]
  def change
    create_table :artifacts do |t|
      t.references :creation_job, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :filename, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
  end
end
