# frozen_string_literal: true
class NevaehConstruction < ApplicationRecord
  belongs_to :creator, class_name: 'User'
  belongs_to :active_release, class_name: 'NevaehConstructionRelease', optional: true
  has_many :releases, class_name: 'NevaehConstructionRelease', dependent: :restrict_with_error
  validates :name, presence: true, length: {maximum: 160}
  validates :key, uniqueness: true, format: {with: /\A[a-z][a-z0-9_]{0,60}\z/}
  validates :status, inclusion: {in: %w[draft active paused]}
  validate :valid_contract
  before_update do
    if will_save_change_to_key? && releases.exists?
      errors.add(:key, 'cannot change after a release; create another construction')
      throw :abort
    end
  end
  def capability_key = "factory.construct.#{key}"
  private
  def valid_contract
    NevaehIntelligences::Factory::Contract.validate!(definition, sample_tests)
  rescue ArgumentError => error
    errors.add(:base, error.message)
  end
end
