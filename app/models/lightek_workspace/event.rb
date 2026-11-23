module LightekWorkspace
  class Event < ApplicationRecord
    self.table_name = 'lightek_shared_events'

    belongs_to :calendar, class_name: 'LightekWorkspace::Calendar'
    belongs_to :organizer, class_name: 'User'
    belongs_to :session_room, class_name: 'LightekSessions::Room', optional: true
    has_many :guests, class_name: 'LightekWorkspace::EventGuest'
    validates :title, presence: true, length: {maximum: 160}
    validates :details, length: {maximum: 4_000}
    validates :starts_at, :ends_at, presence: true
    validate do
      errors.add(:ends_at, 'must be after the start') if starts_at && ends_at && ends_at <= starts_at
    end

    def meeting_participant?(user)
      calendar.employer_id == user.id || organizer_id == user.id || guests.exists?(user: user)
    end

    def meeting_link_available_to?(user)
      session_room && session_room.status != 'ended' && ends_at.future? && meeting_participant?(user)
    end

    def meeting_duration_minutes
      seconds = ends_at - starts_at
      unless seconds % 60 == 0 && seconds.between?(15.minutes, 480.minutes)
        raise ArgumentError, 'A video meeting must last 15–480 whole minutes.'
      end

      (seconds / 60).to_i
    end

    REPEAT_UNITS = {'daily' => :days, 'weekly' => :weeks, 'monthly' => :months}.freeze

    def repeat_attributes(frequency:, count:)
      return [{}] if frequency.blank?

      unit = REPEAT_UNITS.fetch(frequency) { raise ArgumentError, 'Choose a supported repeat frequency.' }
      count = count.to_s
      raise ArgumentError, 'Set 2 to 52 total occurrences.' unless count.match?(/\A[0-9]{1,2}\z/) && count.to_i.between?(2, 52)

      validate!
      key = SecureRandom.uuid
      Array.new(count.to_i) do |offset|
        {series_key: key, starts_at: starts_at.advance(unit => offset), ends_at: ends_at.advance(unit => offset)}
      end
    end

    scope :scheduled, -> { where(cancelled_at: nil) }
    scope :during, ->(first, last) { where('starts_at < ? AND ends_at > ?', last, first) }
  end
end
