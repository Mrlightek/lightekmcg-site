class CreateSusuInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :susu_invitations do |t|
      t.references :susu_group, null: false, foreign_key: true
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :email_address, null: false
      t.integer :payout_position, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :accepted_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :susu_invitations, [:susu_group_id, :email_address], unique: true, name: "idx_susu_invites_group_email"
    add_index :susu_invitations, :status
    add_index :susu_invitations, :expires_at
  end
end
