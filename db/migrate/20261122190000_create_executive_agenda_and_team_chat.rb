class CreateExecutiveAgendaAndTeamChat < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_agenda_items do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :title, null: false, limit: 160
      t.string :category, null: false, limit: 20
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.text :notes
      t.datetime :closed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[user_id starts_at], where: "closed_at IS NULL", name: "index_nevaeh_agenda_on_open_schedule"
      t.check_constraint "ends_at > starts_at", name: "nevaeh_agenda_has_positive_duration"
    end

    create_table :lightek_team_channels do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}, index: false
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false, limit: 60
      t.string :description, limit: 240
      t.boolean :private_channel, null: false, default: true
      t.timestamps

      t.index %i[employer_id name], unique: true
    end

    create_table :lightek_team_memberships do |t|
      t.references :channel, null: false, foreign_key: {to_table: :lightek_team_channels}, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps

      t.index %i[channel_id user_id], unique: true
    end

    create_table :lightek_team_messages do |t|
      t.references :channel, null: false, foreign_key: {to_table: :lightek_team_channels}, index: false
      t.references :author, null: false, foreign_key: {to_table: :users}
      t.references :reply_to, foreign_key: {to_table: :lightek_team_messages}
      t.text :body, null: false
      t.string :request_key, null: false, limit: 36
      t.timestamps

      t.index %i[channel_id id]
      t.index %i[channel_id author_id request_key], unique: true, name: "index_team_messages_on_request"
    end
  end
end
