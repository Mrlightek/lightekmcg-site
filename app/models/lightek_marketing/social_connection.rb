# frozen_string_literal: true
module LightekMarketing
  class SocialConnection < ApplicationRecord
    self.table_name = "lightek_marketing_social_connections"
    belongs_to :site, class_name: "DymondSite::Site"
    validates :provider, inclusion: {in: %w[webhook]}
    validates :account_label, :credential_key, presence: true
    validates :publish_endpoint, format: {with: /\Ahttps:\/\//i}
    validates :account_label, uniqueness: {scope: [:site_id, :provider]}
  end
end
