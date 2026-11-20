# frozen_string_literal: true

module LightekSales
  class SocialProspect < ApplicationRecord
    self.table_name = 'lightek_sales_social_prospects'

    X_ID = /\A[0-9]{1,25}\z/
    X_USERNAME = /\A[a-z0-9_]{1,15}\z/
    PROVIDER_LABELS = {'x' => 'X', 'facebook' => 'Facebook', 'linkedin' => 'LinkedIn',
      'reddit' => 'Reddit', 'google_maps' => 'Google Maps'}.freeze

    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :lead, class_name: 'LightekSales::Lead', optional: true
    belongs_to :saved_by, class_name: 'User'
    belongs_to :contacted_by, class_name: 'User', optional: true

    validates :provider, inclusion: {in: PROVIDER_LABELS.keys}
    validates :source_post_id, format: {with: X_ID}, if: :x?
    validates :remote_id, :sender_id, format: {with: X_ID}, unless: :web_only?
    validates :remote_id, :sender_id, absence: true, if: :web_only?
    validates :web_username, format: {with: X_USERNAME}, allow_nil: true
    validates :web_profile_url, :web_source_url, presence: true, length: {maximum: 1024}, unless: :x?
    validates :web_display_name, length: {maximum: 120}, allow_nil: true
    validates :web_display_name, presence: true, if: :maps?
    validates :business_website_url, length: {maximum: 1024}, allow_nil: true
    validates :website_finding, length: {maximum: 1000}, allow_nil: true
    validates :outreach_status, inclusion: {in: %w[ready sending sent uncertain]}
    validates :contact_permission, length: {maximum: 250}
    validate do
      errors.add(:lead, 'must belong to this website') if lead && lead.site_id != site_id
    end

    def x? = provider == 'x'
    def maps? = provider == 'google_maps'
    def web_only? = !x? || web_username.present?
    def provider_label = PROVIDER_LABELS.fetch(provider)

    def name
      return web_display_name.presence || "#{provider_label} · #{web_profile_url.split('/').last}" unless x?

      web_only? ? "@#{web_username}" : "X profile #{remote_id}"
    end

    def profile_url
      return web_profile_url unless x?

      web_only? ? "https://x.com/#{web_username}" : "https://x.com/i/user/#{remote_id}"
    end

    def source_url
      return web_source_url unless x?

      web_only? ? "#{profile_url}/status/#{source_post_id}" : "https://x.com/i/web/status/#{source_post_id}"
    end

    def thread_url
      "https://x.com/messages/compose?recipient_id=#{remote_id}" unless web_only?
    end
  end
end
