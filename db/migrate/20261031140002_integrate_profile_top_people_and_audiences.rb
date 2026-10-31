# frozen_string_literal: true
class IntegrateProfileTopPeopleAndAudiences < ActiveRecord::Migration[8.0]
  def up
    add_column :profiles, :community_gender, :string, null: false, default: "unspecified" unless column_exists?(:profiles, :community_gender)
    add_column :profiles, :top_people_limit, :integer, null: false, default: 8 unless column_exists?(:profiles, :top_people_limit)
    add_column :communities, :audience, :string, null: false, default: "everyone" unless column_exists?(:communities, :audience)
    add_column :posts, :audience, :string, null: false, default: "everyone" unless column_exists?(:posts, :audience)
    unless table_exists?(:lightek_social_top_people)
      create_table :lightek_social_top_people do |t|
        t.references :profile, null: false, foreign_key: true
        t.references :person, null: false, foreign_key: { to_table: :profiles }
        t.integer :position, null: false
        t.timestamps
      end
    end
    add_index :lightek_social_top_people, %i[profile_id person_id], unique: true, name: "idx_top_people_person" unless index_exists?(:lightek_social_top_people, %i[profile_id person_id], name: "idx_top_people_person")
    add_index :lightek_social_top_people, %i[profile_id position], unique: true, name: "idx_top_people_position" unless index_exists?(:lightek_social_top_people, %i[profile_id position], name: "idx_top_people_position")
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reconciliation preserves schema that may have existed under version 20261031140000"
  end
end
