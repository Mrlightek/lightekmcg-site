class CompleteBroadcastDistribution < ActiveRecord::Migration[8.0]
  def change
    add_reference :studio_hosted_carriages, :fallback_channel, foreign_key: { to_table: :studio_broadcast_channels, on_delete: :nullify }
    add_column :studio_hosted_carriages, :relay_cursor, :jsonb, null: false, default: {}

    add_reference :studio_program_licenses, :parent_license, foreign_key: { to_table: :studio_program_licenses }
    create_table :studio_program_clips do |t|
      t.references :license, null: false, foreign_key: { to_table: :studio_program_licenses }
      t.references :site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.string :title, null: false
      t.integer :start_second, null: false
      t.integer :duration_seconds, null: false
      t.string :error_message
      t.string :public_key, null: false, index: { unique: true }
      t.datetime :withdrawn_at
      t.timestamps
    end
  end
end
