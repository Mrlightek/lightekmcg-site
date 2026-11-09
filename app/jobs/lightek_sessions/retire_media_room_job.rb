module LightekSessions
  class RetireMediaRoomJob < ApplicationJob
    queue_as :default
    retry_on Media::Unavailable, wait: 10.seconds, attempts: 12
    def perform(id, retired_name)
      room = Room.find(id)
      return unless room.retired_media_names.include?(retired_name)
      raise ArgumentError, 'Invalid retired room name' unless retired_name.match?(/\Alightek-[a-f0-9]{40}\z/) && retired_name != room.media_name
      Media.new(room.resource.site).call('DeleteRoom', {room: retired_name}, room: retired_name)
      room.with_lock { room.update!(retired_media_names: room.retired_media_names - [retired_name]) }
    end
  end
end
