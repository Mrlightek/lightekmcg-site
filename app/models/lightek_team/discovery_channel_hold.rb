module LightekTeam
  class DiscoveryChannelHold < ApplicationRecord
    self.table_name = "lightek_discovery_channel_holds"

    belongs_to :matter, class_name: "LightekMail::Matter", inverse_of: :channel_holds
    belongs_to :channel

    scope :active, -> { where(released_at: nil) }

    def self.protect!(record, channel)
      return unless channel

      channel.with_lock do
        if active.exists?(channel: channel)
          record.errors.add(:base, "This Team Chat channel is on a discovery hold.")
          throw :abort
        end
      end
    end
  end
end
