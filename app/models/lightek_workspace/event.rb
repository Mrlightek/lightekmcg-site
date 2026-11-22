module LightekWorkspace
  class Event < ApplicationRecord
    self.table_name = 'lightek_shared_events'

    belongs_to :calendar, class_name: 'LightekWorkspace::Calendar'
    belongs_to :organizer, class_name: 'User'
    has_many :guests, class_name: 'LightekWorkspace::EventGuest'
    validates :title, presence: true, length: {maximum: 160}
    validates :details, length: {maximum: 4_000}
    validates :starts_at, :ends_at, presence: true
    validate do
      errors.add(:ends_at, 'must be after the start') if starts_at && ends_at && ends_at <= starts_at
    end

    scope :scheduled, -> { where(cancelled_at: nil) }
    scope :during, ->(first, last) { where('starts_at < ? AND ends_at > ?', last, first) }
  end
end
