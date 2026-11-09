module LightekSessions
  class CloseRoomJob < ApplicationJob
    queue_as :default
    retry_on Media::Unavailable, wait: 15.seconds, attempts: 10
    def perform(id)
      room = Room.find(id)
      return if room.status != 'ended' && Time.current < room.ends_at
      room.update!(status: 'ended')
      Media.new(room.resource.site).call('DeleteRoom', {room: room.media_name}, room: room.media_name)
    end
  end
end
