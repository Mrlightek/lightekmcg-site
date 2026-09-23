class SusuMembership < ApplicationRecord
  belongs_to :susu_group
  belongs_to :user

  has_many :susu_commitments, dependent: :destroy

  validates :payout_position,
            presence: true,
            numericality: { greater_than: 0 },
            uniqueness: { scope: :susu_group_id }
  validates :user_id, uniqueness: { scope: :susu_group_id }
end
