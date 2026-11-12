class AgencyProfile < ApplicationRecord
  belongs_to :user
  validates :user_id, uniqueness: true
  validates :brand_name, presence: true, length: {maximum: 120}
  validates :logo_url, format: {with: /\Ahttps:\/\/[^\s]+\z/}, allow_blank: true
  validates :support_email, format: {with: URI::MailTo::EMAIL_REGEXP}, allow_blank: true
  validates :accent_color, format: {with: /\A#[0-9a-fA-F]{6}\z/}
  validate { errors.add(:user, "must be a white label agency") unless user&.role == "white_label" }
end
