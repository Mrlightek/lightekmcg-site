class CreateExecutiveWorkAndTeamOffice < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_executive_cases do |t|
      t.references :owner, null: false, foreign_key: {to_table: :users}
      t.references :assignee, foreign_key: {to_table: :users}
      t.references :delivery_message, foreign_key: {to_table: :lightek_mail_messages}
      t.string :kind, null: false, limit: 20
      t.string :title, null: false, limit: 160
      t.text :details
      t.string :status, null: false, default: 'open', limit: 20
      t.datetime :due_at, null: false
      t.datetime :reminded_at
      t.string :reference, limit: 240
      t.string :source_event, limit: 100
      t.text :review_note
      t.references :reviewer, foreign_key: {to_table: :users}
      t.datetime :reviewed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.index %i[owner_id source_event], unique: true
      t.index :due_at, where: "reminded_at IS NULL AND status <> 'closed'", name: 'index_executive_cases_due_for_reminder'
    end
    create_table :nevaeh_executive_phone_routes do |t|
      t.references :owner, null: false, index: {unique: true}, foreign_key: {to_table: :users}
      t.references :assignee, foreign_key: {to_table: :users}
      t.string :key, null: false, limit: 48
      t.timestamps
      t.index :key, unique: true
    end
    create_table :nevaeh_calendar_invitees do |t|
      t.references :agenda_item, null: false, index: false, foreign_key: {to_table: :nevaeh_agenda_items}
      t.references :mailbox, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :message, foreign_key: {to_table: :lightek_mail_messages}
      t.string :recipient, null: false
      t.string :organizer_address, null: false
      t.integer :sequence, null: false, default: 0
      t.integer :agenda_version
      t.boolean :cancelled, null: false, default: false
      t.timestamps
      t.index %i[agenda_item_id recipient], unique: true
    end
    create_table :lightek_office_files do |t|
      t.references :channel, null: false, foreign_key: {to_table: :lightek_team_channels}
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.references :editor, null: false, foreign_key: {to_table: :users}
      t.string :kind, null: false, limit: 16
      t.string :title, null: false, limit: 160
      t.text :content, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
  end
end
