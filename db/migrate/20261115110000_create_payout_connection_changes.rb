class CreatePayoutConnectionChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_payout_connection_changes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :previous_account_id, null: false
      t.string :replacement_account_id, null: false
      t.string :platform_account_id, null: false
      t.boolean :livemode, null: false
      t.timestamps
    end
    add_index :lightek_payout_connection_changes, :replacement_account_id, unique: true, name: 'idx_payout_replacement_account'
  end
end
