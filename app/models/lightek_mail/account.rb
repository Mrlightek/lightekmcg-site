require "digest"
module LightekMail
  class Account < ApplicationRecord
    self.table_name = "lightek_mail_accounts"
    belongs_to :user
    belongs_to :domain, class_name: "LightekMail::Domain"
    belongs_to :auto_template, class_name: "LightekMail::Template", optional: true
    has_many :messages, class_name: "LightekMail::Message", dependent: :restrict_with_error
    has_many :templates, class_name: "LightekMail::Template", dependent: :restrict_with_error
    before_validation { self.address = address.to_s.strip.downcase }
    validates :address, uniqueness: true, format: {with: /\A[a-z0-9][a-z0-9._+-]{0,63}@[a-z0-9.-]+\z/}
    validates :display_name, length: {in: 1..120}
    validates :daily_limit, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 5000}
    validates :minute_limit, :hour_limit, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 5000}
    validates :storage_limit, numericality: {only_integer: true, greater_than: 0}
    validate do
      errors.add(:address, "must use this account’s domain") if address.to_s.split("@").last != domain&.name
      errors.add(:user, "must own the domain") if domain && domain.user_id != user_id
      errors.add(:auto_template, "must belong to this mailbox") if auto_template && auto_template.account_id != id
    end
    def suspended? = suspended_at.present? || CustomerSuspension.exists?(user_id: user_id)
    def sending_ready? = enabled? && !suspended? && domain.verified_at.present?
    def rotate_token!
      token = "lm_#{SecureRandom.hex(32)}"
      update!(token_digest: Digest::SHA256.hexdigest(token), token_hint: token.last(6))
      token
    end
    def self.authenticate(token)
      return if token.to_s.bytesize > 100 || !token.to_s.start_with?("lm_")
      find_by(token_digest: Digest::SHA256.hexdigest(token))
    end
  end
end
