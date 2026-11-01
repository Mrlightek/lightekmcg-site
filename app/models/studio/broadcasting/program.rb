# frozen_string_literal: true
module Studio
  module Broadcasting
    class Program < ApplicationRecord
      self.table_name = "studio_broadcast_programs"
      belongs_to :channel, class_name: "Studio::Broadcasting::Channel"
      belongs_to :post
      validates :starts_at, :ends_at, presence: true
      validate :valid_slot
      private
      def valid_slot
        errors.add(:post, "must belong to the channel application") if post && channel && post.site_id != channel.site_id
        errors.add(:post, "must be an OTT video or live broadcast") if post && (!%w[lightek_streaming octavia].include?(post.distribution) || !%w[video live].include?(post.kind))
        return unless starts_at && ends_at && channel
        errors.add(:ends_at, "must follow the start time") unless ends_at > starts_at
        overlap = self.class.where(channel_id: channel_id).where("starts_at < ? AND ends_at > ?", ends_at, starts_at)
        overlap = overlap.where.not(id: id) if persisted?
        errors.add(:starts_at, "overlaps another program on this channel") if overlap.exists?
      end
    end
  end
end
