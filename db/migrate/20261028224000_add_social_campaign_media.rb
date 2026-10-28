class AddSocialCampaignMedia < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_marketing_campaigns, :media_url, :string, limit: 1200
    add_column :lightek_marketing_social_connections, :disabled_at, :datetime
    add_index :lightek_marketing_social_posts, [:connection_id, :published_at], name: "idx_social_publication_history"
  end
end
