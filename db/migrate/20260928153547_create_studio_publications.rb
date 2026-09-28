class CreateStudioPublications < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_publications do |t|
      t.references :studio_project, null: false, foreign_key: true
      t.references :production, null: true, foreign_key: true
      t.references :artifact, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :destination
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_at
      t.datetime :published_at
      t.string :external_id
      t.string :external_url
      t.string :gatekeeper_operation_id
      t.jsonb :metadata, null: false, default: {}
      t.text :error_message
      t.timestamps
    end

    add_index :studio_publications, :status
    add_index :studio_publications, :platform
    add_index :studio_publications, :scheduled_at
  end
end
