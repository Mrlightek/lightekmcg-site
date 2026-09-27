class SusuGroup < ApplicationRecord
  include Susuable
  include SusuLifecycle

  belongs_to :organizer, class_name: "User"
  has_many :susu_invitations, dependent: :destroy


  validates :name, presence: true
  validates :target_member_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 2 }
end
