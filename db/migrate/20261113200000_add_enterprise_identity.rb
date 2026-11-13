class AddEnterpriseIdentity < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_people_pay_runs, :preparation_scheduled_at, :datetime
    add_reference :lightek_people_pay_runs, :preparation_actor, foreign_key: {to_table: :users}
    add_column :lightek_people_pay_runs, :preparation_token, :string
    add_column :lightek_people_pay_runs, :preparation_state, :string
    add_column :lightek_people_pay_runs, :preparation_error_code, :string
    add_column :users, :people_template_version, :integer, null: false, default: 0
    add_column :sessions, :mfa_verified_at, :datetime
    add_column :sessions, :mfa_enrollment_only, :boolean, null: false, default: false
    add_column :sessions, :identity_connection_id, :bigint
    add_column :lightek_people_employments, :directory_admin, :boolean, null: false, default: false
    add_column :lightek_people_employments, :directory_principal, :string
    add_index :lightek_people_employments, [:employer_id,:directory_principal], unique: true, where: 'directory_principal IS NOT NULL', name: 'idx_employer_directory_principal'
    add_column :lightek_people_employments, :accounting_access, :string, null: false, default: 'none'
    create_table :lightek_identity_organization_policies do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}, index: {unique: true}
      t.boolean :mfa_required, null: false, default: true
      t.timestamps
    end
    create_table :lightek_identity_factors do |t|
      t.references :user, null: false, foreign_key: true, index: {unique: true}
      t.jsonb :secret_box, null: false, default: {}
      t.jsonb :recovery_digests, null: false, default: []
      t.datetime :enabled_at
      t.datetime :expires_at
      t.bigint :last_counter, null: false, default: -1
      t.timestamps
    end
    create_table :lightek_identity_connections do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}, index: {unique: true}
      t.string :slug, null: false, index: {unique: true}
      t.string :issuer, null: false
      t.string :authorization_endpoint, null: false
      t.string :token_endpoint, null: false
      t.string :jwks_uri, null: false
      t.string :client_id, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_foreign_key :sessions, :lightek_identity_connections, column: :identity_connection_id
    create_table :lightek_identity_subjects do |t|
      t.references :connection, null: false, foreign_key: {to_table: :lightek_identity_connections}
      t.references :user, null: false, foreign_key: true
      t.string :subject, null: false
      t.timestamps
    end
    add_index :lightek_identity_subjects, [:connection_id, :subject], unique: true, name: 'idx_identity_subject'
    add_index :lightek_identity_subjects, [:connection_id, :user_id], unique: true, name: 'idx_identity_user'
    create_table :lightek_identity_login_attempts do |t|
      t.references :connection, null: false, foreign_key: {to_table: :lightek_identity_connections}
      t.references :user, foreign_key: true
      t.string :state_digest, null: false, index: {unique: true}
      t.string :browser_digest, null: false
      t.jsonb :secret_box, null: false, default: {}
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    create_table :lightek_identity_resource_grants do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.string :resource_type, null: false
      t.bigint :resource_id, null: false
      t.string :permission, null: false
      t.timestamps
    end
    add_index :lightek_identity_resource_grants, [:employer_id, :subject_type, :subject_id, :resource_type, :resource_id, :permission], unique: true, name: 'idx_directory_grant'
    create_table :lightek_identity_realms do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}, index: {unique: true}
      t.string :domain, null: false
      t.boolean :enabled, null: false, default: true
      t.boolean :auto_join, null: false, default: false
      t.bigint :directory_revision, null: false, default: 0
      t.date :calendar_on
      t.datetime :next_sync_at
      t.timestamps
    end
    create_table :lightek_identity_node_bindings do |t|
      t.references :realm, null: false, foreign_key: {to_table: :lightek_identity_realms}
      t.references :gatekeeper_node, null: false, foreign_key: true, index: {unique: true}
      t.bigint :synced_revision, null: false, default: -1
      t.string :policy_digest
      t.string :status, null: false, default: 'pending'
      t.string :error_code
      t.datetime :synced_at
      t.timestamps
    end
  end
end
