# frozen_string_literal: true

class StudioSceneRender < ApplicationRecord
  belongs_to :studio_scene
  has_many_attached :inputs
  has_one_attached :video

  ACTIVE_STATUSES = %w[queued preparing rendering encoding].freeze
  validates :status, inclusion: { in: ACTIVE_STATUSES + %w[completed failed] }
  validates :progress, inclusion: { in: 0..100 }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  def active? = ACTIVE_STATUSES.include?(status)
end
