# frozen_string_literal: true

module LightekTeam
  class Message < ApplicationRecord
    self.table_name = 'lightek_team_messages'

    belongs_to :channel, class_name: 'LightekTeam::Channel'
    belongs_to :author, class_name: 'User'
    belongs_to :reply_to, class_name: name, optional: true

    normalizes :body, with: ->(body) { body.strip }
    validates :body, presence: true, length: {maximum: 8_000}
    validates :request_key, format: {with: /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/}
    validate :replies_stay_in_channel

    private

    def replies_stay_in_channel
      return unless reply_to && reply_to.channel_id != channel_id

      errors.add(:reply_to, 'must be in this channel')
    end
  end
end
