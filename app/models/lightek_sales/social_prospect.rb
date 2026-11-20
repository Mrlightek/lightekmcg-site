# frozen_string_literal: true

module LightekSales
  class SocialProspect < ApplicationRecord
    self.table_name = 'lightek_sales_social_prospects'

    X_ID = /\A[0-9]{1,25}\z/
    X_USERNAME = /\A[a-z0-9_]{1,15}\z/

    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :lead, class_name: 'LightekSales::Lead', optional: true
    belongs_to :saved_by, class_name: 'User'
    belongs_to :contacted_by, class_name: 'User', optional: true

    validates :provider, inclusion: {in: %w[x]}
    validates :source_post_id, format: {with: X_ID}
    validates :remote_id, :sender_id, format: {with: X_ID}, unless: :web_only?
    validates :remote_id, :sender_id, absence: true, if: :web_only?
    validates :web_username, format: {with: X_USERNAME}, allow_nil: true
    validates :outreach_status, inclusion: {in: %w[ready sending sent uncertain]}
    validates :contact_permission, length: {maximum: 250}
    validate do
      errors.add(:lead, 'must belong to this website') if lead && lead.site_id != site_id
    end

    def web_only? = web_username.present?
    def name = web_only? ? "@#{web_username}" : "X profile #{remote_id}"
    def profile_url = web_only? ? "https://x.com/#{web_username}" : "https://x.com/i/user/#{remote_id}"
    def source_url = web_only? ? "#{profile_url}/status/#{source_post_id}" : "https://x.com/i/web/status/#{source_post_id}"

    def thread_url
      "https://x.com/messages/compose?recipient_id=#{remote_id}" unless web_only?
    end
  end
end
