# frozen_string_literal: true

# This migration comes from dymond_dash (originally 20260514000001)
class CreateDymondDashTables < ActiveRecord::Migration[7.2]
  def change

    create_table :dymond_dash_themes do |t|
      t.string  :name,            null: false
      t.string  :slug,            null: false
      t.boolean :is_preset,       default: false, null: false
      t.string  :sidebar_bg,      default: "#111318"
      t.string  :topbar_bg,       default: "#111318"
      t.string  :accent_primary,  default: "#C4952A"
      t.string  :accent_hover,    default: "#E8B84B"
      t.string  :text_primary,    default: "#F0EEE8"
      t.string  :text_secondary,  default: "#9A9890"
      t.string  :text_muted,      default: "#4E4E5A"
      t.string  :border_color,    default: "rgba(255,255,255,0.07)"
      t.string  :card_bg,         default: "#181B22"
      t.string  :danger_color,    default: "#CD4D3D"
      t.string  :success_color,   default: "#3DAE82"
      t.text    :custom_css
      t.timestamps
    end
    add_index :dymond_dash_themes, :slug, unique: true

    create_table :dymond_dash_app_configs do |t|
      t.string     :app_name,    null: false, default: "Dymond CMS"
      t.string     :tagline
      t.string     :logo_url
      t.string     :favicon_url
      t.references :theme, foreign_key: { to_table: :dymond_dash_themes }
      t.timestamps
    end

    create_table :dymond_dash_nav_sections do |t|
      t.string  :label,    null: false
      t.string  :slug,     null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :dymond_dash_nav_sections, :slug, unique: true

    create_table :dymond_dash_nav_items do |t|
      t.references :section, null: false,
                             foreign_key: { to_table: :dymond_dash_nav_sections }
      t.string  :label,        null: false
      t.string  :icon,         null: false
      t.string  :path_helper,  null: false
      t.string  :badge_method
      t.string  :feature_slug
      t.integer :position,     default: 0
      t.boolean :visible,      default: true
      t.jsonb   :roles_json
      t.timestamps
    end

    create_table :dymond_dash_features do |t|
      t.string  :slug,       null: false
      t.string  :label,      null: false
      t.string  :icon
      t.string  :gem_source
      t.boolean :active,     default: true, null: false
      t.timestamps
    end
    add_index :dymond_dash_features, :slug, unique: true

    create_table :dymond_dash_plan_features do |t|
      t.string  :plan_slug,    null: false
      t.string  :feature_slug, null: false
      t.boolean :active,       default: true, null: false
      t.timestamps
    end
    add_index :dymond_dash_plan_features, %i[plan_slug feature_slug], unique: true

    create_table :dymond_dash_account_plans do |t|
      t.string   :plan_slug,    null: false, default: "starter"
      t.string   :status,       null: false, default: "active"
      t.datetime :trial_ends_at
      t.bigint   :account_id
      t.string   :account_type
      t.timestamps
    end
    add_index :dymond_dash_account_plans, %i[account_type account_id]

    create_table :dymond_dash_ecosystem_gems do |t|
      t.string  :slug,              null: false
      t.string  :display_name,      null: false
      t.text    :description
      t.string  :category
      t.string  :rubygems_name,     null: false
      t.string  :repo_url
      t.string  :current_version
      t.string  :min_plan_required, default: "starter"
      t.string  :icon
      t.jsonb   :dependencies_json
      t.boolean :featured,          default: false
      t.boolean :core,              default: false
      t.timestamps
    end
    add_index :dymond_dash_ecosystem_gems, :slug, unique: true

    create_table :dymond_dash_installed_gems do |t|
      t.references :ecosystem_gem, null: false,
                                   foreign_key: { to_table: :dymond_dash_ecosystem_gems }
      t.string   :installed_version
      t.string   :status,           null: false, default: "pending"
      t.text     :install_log
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :dymond_dash_installed_gems, :status

    create_table :dymond_dash_pending_gemfile_changes do |t|
      t.references :ecosystem_gem, null: false,
                                   foreign_key: { to_table: :dymond_dash_ecosystem_gems }
      t.string   :action,          null: false
      t.string   :gem_name,        null: false
      t.string   :gem_version
      t.boolean  :applied,         default: false, null: false
      t.datetime :applied_at
      t.timestamps
    end
    add_index :dymond_dash_pending_gemfile_changes, :applied

  end
end
