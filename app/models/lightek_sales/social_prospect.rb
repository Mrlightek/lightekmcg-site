# frozen_string_literal: true

module LightekSales
  class SocialProspect < ApplicationRecord
    self.table_name = 'lightek_sales_social_prospects'

    X_ID = /\A[0-9]{1,25}\z/

    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :lead, class_name: 'LightekSales::Lead', optional: true
    belongs_to :saved_by, class_name: 'User'
    belongs_to :contacted_by, class_name: 'User', optional: true

    validates :provider, inclusion: {in: %w[x]}
    validates :remote_id, :source_post_id, :sender_id, format: {with: X_ID}
    validates :outreach_status, inclusion: {in: %w[ready sending sent uncertain]}
    validates :contact_permission, length: {maximum: 250}
    validate do
      errors.add(:lead, 'must belong to this website') if lead && lead.site_id != site_id
    end

    def profile_url = "https://x.com/i/user/#{remote_id}"
    def source_url = "https://x.com/i/web/status/#{source_post_id}"
    def thread_url = "https://x.com/messages/compose?recipient_id=#{remote_id}"
  end
end
