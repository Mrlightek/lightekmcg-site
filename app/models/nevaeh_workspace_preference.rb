# frozen_string_literal: true
class NevaehWorkspacePreference < ApplicationRecord
  belongs_to :user
  validates :user_id, uniqueness: true
  validate :valid_navigation
  private
  def valid_navigation
    self.navigation = NevaehIntelligences::WorkspaceNavigation.normalize(navigation)
  rescue ArgumentError => error
    errors.add(:navigation, error.message)
  end
end
