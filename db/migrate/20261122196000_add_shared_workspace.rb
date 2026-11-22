class AddSharedWorkspace < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_shared_drives do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.string :name, limit: 120, null: false
      t.timestamps
    end

    create_table :lightek_shared_drive_members do |t|
      t.references :drive, null: false, foreign_key: {to_table: :lightek_shared_drives}
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false
      t.index %i[drive_id user_id], unique: true
    end

    create_table :lightek_shared_drive_entries do |t|
      t.references :drive, null: false, foreign_key: {to_table: :lightek_shared_drives}
      t.references :parent, foreign_key: {to_table: :lightek_shared_drive_entries}
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.string :name, limit: 160, null: false
      t.boolean :folder, null: false
      t.timestamps
      t.index %i[drive_id parent_id]
    end

    create_table :lightek_shared_calendars do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.string :name, limit: 120, null: false
      t.timestamps
    end

    create_table :lightek_shared_events do |t|
      t.references :calendar, null: false, foreign_key: {to_table: :lightek_shared_calendars}
      t.references :organizer, null: false, foreign_key: {to_table: :users}
      t.string :title, limit: 160, null: false
      t.text :details
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.datetime :cancelled_at
      t.timestamps
      t.index %i[calendar_id starts_at]
      t.check_constraint 'ends_at > starts_at', name: 'shared_event_positive_duration'
    end

    create_table :lightek_shared_event_guests do |t|
      t.references :event, null: false, foreign_key: {to_table: :lightek_shared_events}
      t.references :user, null: false, foreign_key: true
      t.string :response, default: 'pending', null: false
      t.timestamps
      t.index %i[event_id user_id], unique: true
    end

    create_table :lightek_office_revisions do |t|
      t.references :file, polymorphic: true, null: false, index: false
      t.integer :version, null: false
      t.text :content, null: false
      t.boolean :rich_text, null: false
      t.string :title, null: false
      t.string :editor_name, null: false
      t.timestamps
      t.index %i[file_type file_id version], unique: true, name: 'index_lightek_office_revisions_on_file_and_version'
    end
  end
end
