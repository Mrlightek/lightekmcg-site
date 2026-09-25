class CreateGatekeeperInfrastructure < ActiveRecord::Migration[8.0]
  def change
    create_table :gatekeeper_nodes do |t|
      t.string :name, null: false
      t.string :hostname
      t.string :ip_address, null: false
      t.string :ssh_user, null: false, default: "root"
      t.integer :ssh_port, null: false, default: 22
      t.string :ssh_key_path
      t.string :provider
      t.string :provider_id
      t.string :region
      t.string :status, null: false, default: "unknown"
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_healthcheck_at
      t.timestamps
    end

    add_index :gatekeeper_nodes, :name, unique: true
    add_index :gatekeeper_nodes, :status

    create_table :gatekeeper_projects do |t|
      t.references :gatekeeper_node, null: false, foreign_key: true
      t.string :name, null: false
      t.string :repository, null: false
      t.string :branch, null: false, default: "main"
      t.string :domain, null: false
      t.string :app_root, null: false
      t.string :app_user, null: false, default: "lightek"
      t.string :ruby_version, null: false, default: "3.3.6"
      t.string :rails_env, null: false, default: "production"
      t.string :apache_service_name, null: false, default: "apache2"
      t.string :sidekiq_service_name
      t.string :status, null: false, default: "unknown"
      t.string :deployed_sha
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_deployed_at
      t.datetime :last_healthcheck_at
      t.timestamps
    end

    add_index :gatekeeper_projects, :name, unique: true
    add_index :gatekeeper_projects, :domain, unique: true
    add_index :gatekeeper_projects, :status

    create_table :gatekeeper_operations do |t|
      t.references :gatekeeper_node, null: false, foreign_key: true
      t.references :gatekeeper_project, null: true, foreign_key: true
      t.string :capability, null: false
      t.string :requested_by, null: false
      t.string :status, null: false, default: "queued"
      t.text :command
      t.text :output
      t.integer :exit_status
      t.jsonb :parameters, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.string :error_class
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :gatekeeper_operations, :capability
    add_index :gatekeeper_operations, :status
    add_index :gatekeeper_operations, :created_at

    create_table :gatekeeper_escalations do |t|
      t.references :gatekeeper_operation, null: false, foreign_key: true
      t.string :category, null: false, default: "unknown_condition"
      t.string :status, null: false, default: "open"
      t.text :reason, null: false
      t.text :resolution
      t.boolean :capability_created, null: false, default: false
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :gatekeeper_escalations, :status
    add_index :gatekeeper_escalations, :category
  end
end
