class AddBroadcastContractsAndReporting < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_hosted_carriages, :observed_feed_state, :string

    create_table :studio_broadcast_contracts do |t|
      t.references :site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.references :counterparty, foreign_key: { to_table: :users }
      t.references :carriage_agreement, foreign_key: { to_table: :studio_carriage_agreements }, index: { unique: true }
      t.references :sponsor_package, foreign_key: { to_table: :studio_sponsor_packages }, index: { unique: true }
      t.string :kind, null: false
      t.string :title, null: false
      t.timestamps
    end

    create_table :studio_broadcast_contract_versions do |t|
      t.references :contract, null: false, foreign_key: { to_table: :studio_broadcast_contracts }
      t.references :offered_by, null: false, foreign_key: { to_table: :users }
      t.integer :number, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.json :terms_snapshot, null: false
      t.string :document_digest, null: false
      t.datetime :withdrawn_at
      t.timestamps
      t.index %i[contract_id number], unique: true, name: "index_broadcast_contract_versions_on_number"
    end

    create_table :studio_broadcast_contract_signatures do |t|
      t.references :version, null: false, foreign_key: { to_table: :studio_broadcast_contract_versions }
      t.references :signer, null: false, foreign_key: { to_table: :users }
      t.string :party, null: false
      t.string :signer_name, null: false
      t.string :document_digest, null: false
      t.datetime :signed_at, null: false
      t.index %i[version_id party], unique: true, name: "index_broadcast_contract_signatures_on_party"
    end

    create_table :studio_broadcast_contract_evidence do |t|
      t.references :version, null: false, foreign_key: { to_table: :studio_broadcast_contract_versions }
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.string :reference, null: false
      t.string :kind, null: false
      t.bigint :quantity, null: false
      t.date :occurred_on, null: false
      t.timestamps
      t.index %i[version_id kind reference], unique: true, name: "index_broadcast_contract_evidence_on_reference"
    end

    create_table :studio_broadcast_report_archives do |t|
      t.references :site, null: false, foreign_key: { to_table: :dymond_site_sites }
      t.date :month, null: false
      t.text :csv, null: false
      t.timestamps
      t.index %i[site_id month], unique: true
    end

    create_table :studio_broadcast_feed_incidents do |t|
      t.references :hosted_carriage, null: false, foreign_key: { to_table: :studio_hosted_carriages, on_delete: :cascade }
      t.string :event, null: false
      t.timestamps
      t.index %i[hosted_carriage_id created_at], name: "index_broadcast_feed_incidents_on_time"
    end
  end
end
