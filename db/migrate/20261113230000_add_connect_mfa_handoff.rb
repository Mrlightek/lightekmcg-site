class AddConnectMfaHandoff < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_connect_grants, :authorization_session,
      foreign_key: {to_table: :sessions, on_delete: :nullify}
    add_column :lightek_connect_grants, :approved_at, :datetime
    add_column :lightek_connect_grants, :delegation_expires_at, :datetime
    add_column :lightek_identity_organization_policies, :connect_mfa_allowed, :boolean, null: false, default: true
  end
end
