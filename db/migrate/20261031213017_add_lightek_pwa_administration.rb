# frozen_string_literal: true
class AddLightekPwaAdministration < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_applications do |t|
      t.references :site, null: false, index: {unique: true}, foreign_key: {to_table: :dymond_site_sites}
      t.string :name
      t.string :short_name
      t.text :description
      t.string :theme_color, default: "#c9a34b", null: false
      t.string :background_color, default: "#07070a", null: false
      t.string :status, default: "published", null: false
      t.string :start_surface, default: "home", null: false
      t.string :support_email
      t.text :welcome_message
      t.jsonb :settings, default: {}, null: false
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
    create_table :lightek_pwa_memberships do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :profile, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :lightek_pwa_memberships, [:site_id, :profile_id], unique: true, name: "idx_pwa_site_profile"
    create_table :lightek_pwa_admin_events do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :action, null: false
      t.string :record_type
      t.bigint :record_id
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_column :posts, :moderation_state, :string, null: false, default: "published"
    add_column :communities, :moderation_state, :string, null: false, default: "active"
    add_index :posts, [:site_id, :moderation_state]
    add_index :communities, [:site_id, :moderation_state]
  end
end
