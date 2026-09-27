class SusuInvitation < ApplicationRecord
  STATUSES = %w[pending accepted cancelled expired].freeze
  belongs_to :susu_group
  belongs_to :inviter, class_name: "User"

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :payout_position, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :expires_at, presence: true

  scope :pending, -> { where(status: "pending") }

  def expired? = expires_at <= Time.current

  def accept_for!(user)
    raise ArgumentError, "Invitation has expired" if expired?
    raise ArgumentError, "Invitation email does not match this account" unless user.email_address.casecmp?(email_address)

    transaction do
      membership = susu_group.susu_memberships.find_or_create_by!(user: user) do |record|
        record.payout_position = payout_position
      end
      user.grant_feature!(:susu, source: "susu_invitation") if user.respond_to?(:grant_feature!)
      update!(status: "accepted", accepted_at: Time.current)
      membership
    end
  end

  def invitation_token
    signed_id(purpose: :susu_invitation, expires_in: 14.days)
  end

  def self.find_by_invitation_token!(token)
    find_signed!(token, purpose: :susu_invitation)
  end
end
