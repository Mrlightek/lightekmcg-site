class AddGrowthSearchEvidence < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_growth_search_snapshots do |t|
      t.bigint :site_id, null: false, index: true
      t.bigint :created_by_id, null: false
      t.string :property, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.json :rows, null: false
      t.json :inspection
      t.timestamps
    end

    create_table :lightek_growth_backlinks do |t|
      t.bigint :site_id, null: false
      t.bigint :updated_by_id, null: false
      t.string :fingerprint, null: false
      t.text :source_url, null: false
      t.text :target_url, null: false
      t.string :status, null: false
      t.text :outreach_draft
      t.bigint :approved_by_id
      t.datetime :approved_at
      t.timestamps
      t.index %i[site_id fingerprint], unique: true
    end
  end
end
