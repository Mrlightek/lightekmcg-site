require 'uri'
module LightekGrowth
  class Link < ApplicationRecord
    self.table_name = 'lightek_growth_links'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :campaign, class_name: 'LightekMarketing::Campaign'
    belongs_to :created_by, class_name: 'User'
    before_validation(on: :create) { self.token ||= SecureRandom.hex(16) }
    validates :label, presence: true, length: {maximum: 160}
    validates :token, presence: true, uniqueness: true
    validates :source, :medium, format: {with: /\A[a-z0-9][a-z0-9_-]{0,79}\z/}
    validates :destination_path, length: {maximum: 500}
    validate do
      errors.add(:campaign, 'must belong to this website') if campaign && campaign.site_id != site_id
      # Only same-host paths, without user-supplied queries, encodings or fragments.
      errors.add(:destination_path, 'must be a local path such as /shop, without a query or fragment') unless destination_path.to_s.match?(%r{\A/(?:[a-zA-Z0-9_./~-])*\z}) && !destination_path.to_s.start_with?('//') && !destination_path.to_s.split('/').include?('..')
      if persisted? && (changes.keys & %w[site_id campaign_id token source medium destination_path]).any?
        errors.add(:base, 'Create a new link to change its campaign, source or destination; historical links are retained')
      end
    end
    def destination_url
      URI::HTTPS.build(host: site.host, path: destination_path, query: URI.encode_www_form(utm_source: source, utm_medium: medium, utm_campaign: "campaign-#{campaign_id}")).to_s
    end
  end
end
