# frozen_string_literal: true
class NevaehOsAgent < ApplicationRecord
  belongs_to :user
  has_many :agent_workers,class_name:'NevaehAgentWorker',dependent: :restrict_with_error
  validates :autonomy,inclusion:{in:%w[manual scheduled]}
  validate do
    errors.add(:allowed_capabilities,'must be an array of capability names or prefixes') unless allowed_capabilities.is_a?(Array) && allowed_capabilities.size<=100 && allowed_capabilities.all? { |v| v.is_a?(String) && v.match?(/\A[a-z][a-z0-9_.]*(?:\.\*)?\z/) }
  end
  validates :name, presence: true, length: {maximum: 40}
  validates :role, length: {maximum: 80}
  validates :instructions, length: {maximum: 4000}
  validates :birth_place, length: {maximum: 160}
end
