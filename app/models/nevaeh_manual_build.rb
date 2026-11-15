# frozen_string_literal: true
class NevaehManualBuild < ApplicationRecord
  belongs_to :creator, class_name: 'User'
  has_many :bindings, class_name: 'NevaehLanguageBinding', dependent: :restrict_with_error
  validates :name, presence: true, length: {maximum: 160}
  validates :status, inclusion: {in: %w[queued running ready failed]}
end
