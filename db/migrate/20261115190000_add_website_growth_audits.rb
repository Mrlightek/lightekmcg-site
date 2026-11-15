class AddWebsiteGrowthAudits < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_growth_page_metadata do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :page, null: false, foreign_key: {to_table: :dymond_site_pages, on_delete: :cascade}, index: {unique: true}
      t.references :updated_by, null: false, foreign_key: {to_table: :users}
      t.string :title_tag
      t.text :description
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :lightek_growth_website_audits do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.bigint :scope_page_id
      t.string :request_key, :status, :rules_version, null: false
      t.jsonb :page_results, null: false, default: []
      t.jsonb :summary, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_growth_website_audits, [:site_id, :request_key], unique: true, name: 'idx_website_audit_request'
    create_table :lightek_growth_audit_findings do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :website_audit, null: false, foreign_key: {to_table: :lightek_growth_website_audits}
      t.bigint :page_id, null: false
      t.string :rule, :locator, :severity, :title, null: false
      t.string :status, null: false, default: 'open'
      t.jsonb :evidence, :fix_target, null: false, default: {}
      t.text :resolution_note
      t.references :resolved_by, foreign_key: {to_table: :users}
      t.datetime :resolved_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :lightek_growth_audit_fixes do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :finding, null: false, foreign_key: {to_table: :lightek_growth_audit_findings}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :applied_by, :rolled_back_by, foreign_key: {to_table: :users}
      t.string :status, null: false, default: 'prepared'
      t.string :baseline, :applied_fingerprint
      t.jsonb :before_values, :after_values, :verification, null: false, default: {}
      t.datetime :applied_at, :rolled_back_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
  end
end
