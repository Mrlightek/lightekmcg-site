class StudioLiveViewer < ApplicationRecord
  self.table_name = 'lightek_live_viewers'
  belongs_to :studio_live_operation
  belongs_to :user
  scope :present_now, -> { where('last_seen_at > ?', 45.seconds.ago) }
end
