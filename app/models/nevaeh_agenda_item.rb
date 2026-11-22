# frozen_string_literal: true

class NevaehAgendaItem < ApplicationRecord
  CATEGORIES = {
    'meeting' => 'Meeting',
    'personal' => 'Personal or family',
    'travel' => 'Travel and logistics',
    'screening' => 'Screening or pitch',
    'follow_up' => 'Follow-up or decision'
  }.freeze

  belongs_to :user
  validates :title, presence: true, length: {maximum: 160}
  validates :category, inclusion: {in: CATEGORIES.keys}
  validates :starts_at, :ends_at, presence: true
  validates :notes, length: {maximum: 4_000}
  validate :ends_after_start
  scope :open_items, -> { where(closed_at: nil) }
  scope :overlapping, ->(starts_at, ends_at) { where('starts_at < ? AND ends_at > ?', ends_at, starts_at) }

  def category_label
    CATEGORIES.fetch(category)
  end

  def overlap_count
    self.class.where(user_id: user_id).open_items.where.not(id: id).overlapping(starts_at, ends_at).count
  end

  private

  def ends_after_start
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, 'must be after the start')
  end
end
