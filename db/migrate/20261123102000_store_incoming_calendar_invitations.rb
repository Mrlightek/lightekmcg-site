class StoreIncomingCalendarInvitations < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_mail_messages, :calendar_notice, :jsonb, default: {}, null: false

    create_table :lightek_mail_calendar_invitations do |t|
      t.references :account, null: false, index: false, foreign_key: {to_table: :lightek_mail_accounts, on_delete: :cascade}
      t.references :source_message, foreign_key: {to_table: :lightek_mail_messages, on_delete: :nullify}
      t.references :reply_message, foreign_key: {to_table: :lightek_mail_messages, on_delete: :nullify}
      t.string :uid, null: false, limit: 255
      t.string :organizer, null: false, limit: 254
      t.string :attendee, null: false, limit: 254
      t.string :title, null: false, limit: 160
      t.text :description
      t.string :location, limit: 300
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :all_day, null: false, default: false
      t.integer :sequence, null: false
      t.datetime :stamp, null: false
      t.string :response, null: false, default: "pending"
      t.datetime :reply_stamp
      t.integer :response_revision, null: false, default: 0
      t.boolean :cancelled, null: false, default: false
      t.timestamps

      t.index %i[account_id attendee organizer uid], unique: true, name: "idx_mail_calendar_invitation_identity"
      t.index %i[account_id attendee starts_at], name: "idx_mail_calendar_invitation_agenda"
    end
  end
end
