class CreateSharedCalendarExternalInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_shared_external_invitations do |t|
      t.references :event, null: false, index: false, foreign_key: {to_table: :lightek_shared_events, on_delete: :cascade}
      t.references :mailbox, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :message, foreign_key: {to_table: :lightek_mail_messages, on_delete: :nullify}
      t.string :organizer_address, null: false, limit: 254
      t.string :attendee_address, null: false, limit: 254
      t.string :uid, null: false
      t.integer :sequence, null: false, default: 0
      t.string :response, null: false, default: 'pending'
      t.datetime :reply_timestamp
      t.string :delivery_error
      t.timestamps

      t.index [:event_id, :attendee_address], unique: true
      t.index :uid, unique: true
    end
  end
end
