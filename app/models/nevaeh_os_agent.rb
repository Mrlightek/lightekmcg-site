# frozen_string_literal: true
class NevaehOsAgent < ApplicationRecord
  belongs_to :user
  validates :name, presence: true, length: {maximum: 40}
  validates :role, length: {maximum: 80}
  validates :instructions, length: {maximum: 4000}
  validates :birth_place, length: {maximum: 160}
end
