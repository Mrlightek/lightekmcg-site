class CreateLightekSales < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_sales_accounts do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :owner, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :website
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_accounts, [:site_id, :normalized_name], unique: true, name: 'idx_sales_account_name'
    add_reference :lightek_marketing_contacts, :sales_account, foreign_key: {to_table: :lightek_sales_accounts}
    add_reference :lightek_marketing_contacts, :sales_owner, foreign_key: {to_table: :users}
    add_column :lightek_marketing_contacts, :name, :string
    add_column :lightek_marketing_contacts, :phone, :string
    add_column :lightek_marketing_contacts, :job_title, :string
    add_column :lightek_marketing_contacts, :sales_notes, :text
    add_column :lightek_marketing_contacts, :lock_version, :integer, null: false, default: 0
    create_table :lightek_sales_opportunities do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :owner, foreign_key: {to_table: :users}
      t.references :account, null: false, foreign_key: {to_table: :lightek_sales_accounts}
      t.references :contact, foreign_key: {to_table: :lightek_marketing_contacts}
      t.string :name, null: false
      t.string :stage, null: false, default: 'discovery'
      t.string :forecast_category, null: false, default: 'pipeline'
      t.bigint :amount_cents, null: false, default: 0
      t.string :currency, null: false, default: 'USD'
      t.integer :probability, null: false, default: 10
      t.date :close_on, null: false
      t.string :next_step
      t.date :follow_up_on
      t.text :notes
      t.string :loss_reason
      t.datetime :stage_changed_at
      t.datetime :closed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_opportunities, [:site_id, :stage, :close_on], name: 'idx_sales_pipeline'
    add_check_constraint :lightek_sales_opportunities, 'amount_cents >= 0 AND probability >= 0 AND probability <= 100', name: 'sales_opportunity_amount_probability'
    create_table :lightek_sales_leads do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :owner, foreign_key: {to_table: :users}
      t.references :opportunity, foreign_key: {to_table: :lightek_sales_opportunities}
      t.string :name, null: false
      t.string :email, null: false
      t.string :company, null: false
      t.string :phone
      t.string :source, null: false, default: 'manual'
      t.string :status, null: false, default: 'new'
      t.string :next_step
      t.date :follow_up_on
      t.text :notes
      t.datetime :converted_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_leads, [:site_id, :email], unique: true
    add_index :lightek_sales_leads, [:site_id, :status, :follow_up_on], name: 'idx_sales_lead_follow_up'
    create_table :lightek_sales_routing_rules do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :owner, null: false, foreign_key: {to_table: :users}
      t.string :source, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_sales_routing_rules, [:site_id, :source], unique: true
    create_table :lightek_sales_activities do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :kind, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :lightek_sales_activities, [:site_id, :record_type, :record_id, :created_at], name: 'idx_sales_activity_timeline'
  end
end
