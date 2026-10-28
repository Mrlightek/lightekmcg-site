# frozen_string_literal: true
module LightekMarketing
  class Contact < ApplicationRecord
    self.table_name = "lightek_marketing_contacts"
    belongs_to :site, class_name: "DymondSite::Site"
    validates :email, presence: true, uniqueness: {scope: :site_id}, format: {with: URI::MailTo::EMAIL_REGEXP}
    before_validation { self.email = email.to_s.strip.downcase }
    scope :subscribed, -> { where.not(subscribed_at: nil).where(unsubscribed_at: nil) }
  end
end
