class AddGrowthFoundation < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_growth_briefs do |t|
      t.references :site, null: false, index: {unique: true}, foreign_key: {to_table: :dymond_site_sites}
      t.references :updated_by, null: false, foreign_key: {to_table: :users}
      t.text :offering, :audience, :customer_problem, :value_proposition, :voice, :goal
      t.date :goal_on
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :lightek_growth_links do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.string :token, null: false, index: {unique: true}
      t.string :label, :source, :medium, :destination_path, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    create_table :lightek_growth_visits do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :link, null: false, foreign_key: {to_table: :lightek_growth_links}
      t.string :token, null: false, index: {unique: true}
      t.timestamps
    end
    add_index :lightek_growth_visits, [:site_id, :created_at]
    %i[website_template_inquiries lightek_sales_leads lightek_sales_opportunities lightek_commerce_orders].each do |table|
      add_reference table, :growth_visit, foreign_key: {to_table: :lightek_growth_visits}
    end
  end
end
