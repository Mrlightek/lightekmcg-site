class CreateBroadcastOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_program_licenses, :additional_rights, :jsonb, default: [], null: false
    add_column :studio_broadcast_channels, :backup_asset_id, :bigint
    add_column :studio_broadcast_channels, :backup_blob_id, :bigint

    create_table :studio_carriage_agreements do |t|
      t.references :outlet_site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.references :station_site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.references :channel, foreign_key: { to_table: :studio_broadcast_channels }
      t.references :hosted_carriage, foreign_key: { to_table: :studio_hosted_carriages }
      t.check_constraint "(channel_id IS NULL) <> (hosted_carriage_id IS NULL)", name: "studio_carriage_agreement_source"
      t.references :offered_by, null: false, foreign_key: { to_table: :users }
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.datetime :accepted_at
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.jsonb :terms, null: false
      t.timestamps
    end

    create_table :studio_sponsor_packages do |t|
      t.references :site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.string :name, null: false
      t.string :public_key, null: false, index: { unique: true }
      t.timestamps
    end

    create_table :studio_sponsor_package_spots do |t|
      t.references :package, null: false, foreign_key: { to_table: :studio_sponsor_packages }
      t.references :payment, null: false, index: { unique: true }, foreign_key: { to_table: :studio_ad_payments }
      t.timestamps
    end

    create_table :studio_broadcast_operating_plans do |t|
      t.references :site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.references :department, null: false, foreign_key: { to_table: :lightek_people_departments }
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.references :channel, foreign_key: { to_table: :studio_broadcast_channels }
      t.string :market
      t.date :month, null: false
      t.text :coverage, null: false
      t.text :targets, null: false
      t.bigint :budget_cents, null: false
      t.bigint :actual_cost_cents, null: false
      t.bigint :actual_revenue_cents, null: false
      t.timestamps
    end
  end
end
