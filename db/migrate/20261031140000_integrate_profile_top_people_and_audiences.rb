# frozen_string_literal: true
class IntegrateProfileTopPeopleAndAudiences < ActiveRecord::Migration[8.0]
  def change
    add_column :profiles, :community_gender, :string, null: false, default: "unspecified"
    add_column :profiles, :top_people_limit, :integer, null: false, default: 8
    add_column :communities, :audience, :string, null: false, default: "everyone"
    add_column :posts, :audience, :string, null: false, default: "everyone"
    create_table :lightek_social_top_people do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: { to_table: :profiles }
      t.integer :position, null: false
      t.timestamps
    end
    add_index :lightek_social_top_people, %i[profile_id person_id], unique: true, name: "idx_top_people_person"
    add_index :lightek_social_top_people, %i[profile_id position], unique: true, name: "idx_top_people_position"
  end
end
