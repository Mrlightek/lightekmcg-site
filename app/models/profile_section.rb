class ProfileSection < ApplicationRecord
  belongs_to :profile

  validates :key,
            presence: true,
            uniqueness: {
              scope: :profile_id
            }

  validates :position,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validate :settings_must_be_an_object

  scope :ordered,
        -> {
          order(
            :position,
            :id
          )
        }

  private

  def settings_must_be_an_object
    return if settings.is_a?(Hash)

    errors.add(
      :settings,
      "must be a JSON object"
    )
  end
end
