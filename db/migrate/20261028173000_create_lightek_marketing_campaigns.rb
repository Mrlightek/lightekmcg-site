class CreateLightekMarketingCampaigns < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_marketing_campaigns do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :name, null: false, limit: 160
      t.string :channel, null: false, default: "landing_page"
      t.string :status, null: false, default: "draft"
      t.string :headline, limit: 200
      t.text :message
      t.string :cta_label, limit: 60
      t.string :cta_url, limit: 400
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps
    end
    add_index :lightek_marketing_campaigns, [:site_id, :status]
  end
end
