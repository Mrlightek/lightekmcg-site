class UserFeatureEntitlement < ApplicationRecord
  belongs_to :user
  validates :feature_slug, presence: true, uniqueness: { scope: :user_id }
  validates :source, presence: true
  scope :active, -> { where(active: true) }

  def revoke!
    update!(active: false, revoked_at: Time.current)
  end
end
