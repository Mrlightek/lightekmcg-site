# frozen_string_literal: true
module LightekMarketing
  class SocialPost < ApplicationRecord
    self.table_name = "lightek_marketing_social_posts"
    belongs_to :campaign, class_name: "LightekMarketing::Campaign"
    belongs_to :connection, class_name: "LightekMarketing::SocialConnection"
    validates :status, inclusion: {in: %w[pending published failed needs_review]}
    validates :connection_id, uniqueness: {scope: :campaign_id}
    validate :same_site
    def same_site
      errors.add(:connection, "must belong to campaign site") if connection && campaign && connection.site_id != campaign.site_id
    end
  end
end
