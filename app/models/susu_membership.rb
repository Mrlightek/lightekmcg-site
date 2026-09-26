class SusuMembership < ApplicationRecord
  belongs_to :susu_group
  belongs_to :user

  has_many :susu_commitments, dependent: :destroy

  validates :payout_position,
            presence: true,
            numericality: { greater_than: 0 },
            uniqueness: { scope: :susu_group_id }
  validates :user_id, uniqueness: { scope: :susu_group_id }
  after_create_commit :grant_susu_feature_entitlement

  private

  def grant_susu_feature_entitlement
    user.grant_feature!(:susu, source: "susu_membership") if user.respond_to?(:grant_feature!)
  end

end
