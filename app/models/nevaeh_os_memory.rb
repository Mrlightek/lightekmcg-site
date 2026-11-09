# frozen_string_literal: true
class NevaehOsMemory < ApplicationRecord
  belongs_to :user
  validates :category, inclusion: {in: NevaehOsConsent::CATEGORIES}
  validates :text, presence: true, length: {maximum: 4000}
end
