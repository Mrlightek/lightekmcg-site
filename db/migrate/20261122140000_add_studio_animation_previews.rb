class AddStudioAnimationPreviews < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_animation_previews do |t|
      t.references :studio_asset, null: false, foreign_key: true
      t.string :variant_digest, null: false
      t.json :settings, null: false
      t.string :status, null: false, default: "queued"
      t.string :attempt_token, null: false
      t.timestamps
    end
    add_index :studio_animation_previews, [:studio_asset_id, :variant_digest], unique: true
  end
end
