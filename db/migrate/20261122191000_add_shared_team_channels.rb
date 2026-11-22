class AddSharedTeamChannels < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_team_partnerships do |t|
      t.references :channel, null: false, foreign_key: {to_table: :lightek_team_channels}, index: {unique: true}
      t.references :partner, null: false, foreign_key: {to_table: :users}
      t.datetime :accepted_at
      t.datetime :closed_at
      t.timestamps
    end

    create_table :lightek_team_partner_memberships do |t|
      t.references :partnership, null: false, foreign_key: {to_table: :lightek_team_partnerships}, index: false
      t.references :user, null: false, foreign_key: true
      t.index %i[partnership_id user_id], unique: true, name: 'index_team_partner_members_on_partnership_and_user'
    end

    add_reference :lightek_team_messages, :organization, foreign_key: {to_table: :users}
  end
end
