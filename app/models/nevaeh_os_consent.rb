# frozen_string_literal: true
class NevaehOsConsent < ApplicationRecord
  belongs_to :user
  CATEGORIES = ['Conversations', 'Goals & projects', 'Birth data', 'Preferences', 'Faith practices'].freeze
  validates :category, inclusion: {in: CATEGORIES}, uniqueness: {scope: :user_id}
end
