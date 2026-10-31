class CreateGatekeeperFleetUpdates < ActiveRecord::Migration[8.0]
  def change
    create_table :gatekeeper_installations do |t|
      t.references :gatekeeper_node, null: false, foreign_key: true
      t.string :domain, null: false
      t.string :channel, null: false, default: "stable"
      t.boolean :automatic_updates, null: false, default: false
      t.boolean :enabled, null: false, default: true
      t.string :current_version
      t.string :current_image
      t.datetime :last_verified_at
      t.timestamps
    end
    add_index :gatekeeper_installations, :domain, unique: true
    create_table :gatekeeper_releases do |t|
      t.string :version, null: false
      t.string :source_sha, null: false
      t.string :image, null: false
      t.string :channel, null: false, default: "stable"
      t.text :notes
      t.boolean :backward_compatible, null: false, default: false
      t.string :created_by, null: false
      t.timestamps
    end
    add_index :gatekeeper_releases, :version, unique: true
    create_table :gatekeeper_rollouts do |t|
      t.references :gatekeeper_release, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.string :requested_by, null: false
      t.integer :canary_size, null: false, default: 1
      t.integer :batch_size, null: false, default: 10
      t.boolean :auto_promote, null: false, default: false
      t.boolean :promoted, null: false, default: false
      t.datetime :scheduled_at
      t.text :message
      t.timestamps
    end
    add_index :gatekeeper_rollouts, :status
    create_table :gatekeeper_update_targets do |t|
      t.references :gatekeeper_rollout, null: false, foreign_key: true
      t.references :gatekeeper_installation, null: false, foreign_key: true, index: false
      t.references :gatekeeper_operation, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.boolean :canary, null: false, default: false
      t.string :previous_version
      t.string :previous_image
      t.jsonb :receipt, null: false, default: {}
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :gatekeeper_update_targets, [:gatekeeper_rollout_id, :gatekeeper_installation_id], unique: true, name: "index_fleet_target_once"
    add_index :gatekeeper_update_targets, :gatekeeper_installation_id
    add_index :gatekeeper_update_targets, [:gatekeeper_rollout_id, :status], name: "index_fleet_target_status"
    # Database arbitration also protects simultaneous Start requests on different web workers.
    add_index :gatekeeper_update_targets, :gatekeeper_installation_id, unique: true,
      where: "status IN ('reserved', 'queued', 'running', 'failed')", name: "index_fleet_active_installation"
  end
end
