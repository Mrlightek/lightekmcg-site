# frozen_string_literal: true
class CompleteLightekCommunity < ActiveRecord::Migration[8.0]
  def change
    add_reference :communities, :owner_profile, foreign_key: { to_table: :profiles }
    add_reference :communities, :site, foreign_key: { to_table: :dymond_site_sites }
    add_column :communities, :request_key, :string
    add_index :communities, %i[owner_profile_id request_key], unique: true, name: "idx_community_request_unique"
    add_column :communities, :name, :string
    add_column :communities, :slug, :string
    add_column :communities, :description, :text
    add_column :communities, :visibility, :string, default: "public", null: false
    add_column :communities, :sections, :jsonb, default: %w[featured live conversations clips events members playlists about], null: false
    add_index :communities, :slug, unique: true

    create_table :lightek_community_memberships do |t|
      t.references :community, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :lightek_community_memberships, %i[community_id profile_id], unique: true, name: "idx_community_member_unique"

    add_reference :posts, :community, foreign_key: true
    add_reference :posts, :site, foreign_key: { to_table: :dymond_site_sites }
    add_reference :posts, :parent, foreign_key: { to_table: :posts }
    add_column :posts, :title, :string
    add_column :posts, :kind, :string, default: "post", null: false
    add_column :posts, :visibility, :string, default: "public", null: false
    add_column :posts, :metadata, :jsonb, default: {}, null: false
    add_column :posts, :expires_at, :datetime
    add_column :posts, :request_key, :string
    add_index :posts, %i[user_id request_key], unique: true
    add_index :posts, %i[site_id community_id created_at]

    create_table :lightek_community_engagements do |t|
      t.references :post, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.string :kind, null: false
      t.timestamps
    end
    add_index :lightek_community_engagements, %i[post_id profile_id kind], unique: true, name: "idx_community_engagement_unique"
  end
end
