class AddSusuEntitlementsAndConnectPayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :user_feature_entitlements do |t|
      t.references :user, null: false, foreign_key: true
      t.string :feature_slug, null: false
      t.string :source, null: false, default: "manual"
      t.boolean :active, null: false, default: true
      t.datetime :granted_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :user_feature_entitlements, [:user_id, :feature_slug], unique: true,
              name: "idx_user_feature_entitlements_unique"

    add_column :users, :stripe_connect_account_id, :string
    add_column :users, :stripe_connect_details_submitted, :boolean, null: false, default: false
    add_column :users, :stripe_connect_payouts_enabled, :boolean, null: false, default: false
    add_column :users, :stripe_connect_onboarded_at, :datetime
    add_index :users, :stripe_connect_account_id, unique: true

    add_column :susu_rounds, :dymond_bank_payout_id, :bigint
    add_index :susu_rounds, :dymond_bank_payout_id
  end
end
