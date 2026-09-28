class CreateCreationJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :creation_jobs do |t|
      t.references :studio_scene, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.jsonb :manifest, null: false, default: {}
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :creation_jobs, :status
  end
end
