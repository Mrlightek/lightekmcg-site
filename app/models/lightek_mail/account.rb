require "digest"
module LightekMail
  class Account < ApplicationRecord
    self.table_name = "lightek_mail_accounts"
    scope :available, -> { where(deleted_at: nil) }
    scope :mailboxes, -> { available.where(mailbox_kind: "mailbox") }
    scope :groups, -> { available.where(mailbox_kind: "group") }
    has_many :group_memberships, class_name: "LightekMail::GroupMember", foreign_key: :group_id, dependent: :destroy
    has_many :members, through: :group_memberships, source: :member
    validates :spam_filter_level, inclusion: {in: %w[standard strict]}
    validate do
      [allowed_senders, blocked_senders].each do |entries|
        unless entries.is_a?(Array) && entries.size <= 200 && entries.all? { |entry| entry.is_a?(String) && entry.bytesize <= 254 && entry.match?(/\A(?:[a-z0-9][a-z0-9._+\-]*@)?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/) }
          errors.add(:base, "Use at most 200 plain sender addresses or domains per spam list.")
        end
      end
    end
    validates :mailbox_kind, inclusion: {in: %w[mailbox group]}
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
    def sending_ready? = deleted_at.nil? && mailbox_kind == "mailbox" && enabled? && !suspended? && domain.verified_at.present?
    def retire!
      with_lock do
        GroupMember.where("group_id = ? OR member_id = ?", id, id).destroy_all
        self.original_address ||= address
        self.address = "retired-#{id}-#{SecureRandom.hex(4)}@#{domain.name}"
        self.deleted_at = Time.current
        self.enabled = false
        self.token_digest = self.token_hint = nil
        self.auto_reply_enabled = false
        save!
      end
    end
    def rotate_token!
      token = "lm_#{SecureRandom.hex(32)}"
      update!(token_digest: Digest::SHA256.hexdigest(token), token_hint: token.last(6))
      token
    end
    def self.authenticate(token)
      return if token.to_s.bytesize > 100 || !token.to_s.start_with?("lm_")
      mailboxes.find_by(token_digest: Digest::SHA256.hexdigest(token))
    end
  end
end
