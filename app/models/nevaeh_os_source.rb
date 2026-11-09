# frozen_string_literal: true
class NevaehOsSource < ApplicationRecord
  belongs_to :user
  validates :url, :title, :body, :sha256, presence: true
  validates :status, inclusion: {in: %w[draft reviewed]}
  validates :body, length: {maximum: 100000}
end
