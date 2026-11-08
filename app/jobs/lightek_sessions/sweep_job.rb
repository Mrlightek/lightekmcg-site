module LightekSessions
  class SweepJob < ApplicationJob
    queue_as :default
    def perform
      StudioLiveViewer.where('last_seen_at < ?', 1.day.ago).delete_all
      LightekAudienceLease.where('expires_at <= ?', Time.current).delete_all
      Room.where("retired_media_names <> '[]'").find_each { |room| room.retired_media_names.each { |name| RetireMediaRoomJob.perform_later(room.id, name) } }
      Room.where(status: 'ended').where('updated_at > ?', 1.day.ago).find_each { |room| CloseRoomJob.perform_later(room.id) }
      Room.where(status: 'open').find_each do |room|
        if Time.current >= room.ends_at || !room.resource.native_session?
          room.update!(status: 'ended')
          CloseRoomJob.perform_later(room.id)
          next
        end
        media = Media.new(room.resource.site)
        info = media.call('ListParticipants', {room: room.media_name}, room: room.media_name)
        Array(info['participants']).each do |participant|
          match = participant['identity'].to_s.match(/\Auser-(\d+)(-studio)?\z/)
          user = match && User.find_by(id: match[1])
          begin
            Access.authorize!(room, user, joining: false)
            Access.host!(room, user) if match && match[2]
            raise Access::Denied if !room.host?(user) && room.members.find_by(user: user)&.status != 'admitted'
          rescue Access::Denied
            media.call('RemoveParticipant', {room: room.media_name, identity: participant['identity']}, room: room.media_name)
          end
        end
      rescue Media::Unavailable => error
        Rails.logger.warn("[Session media] reconciliation deferred room=#{room.id} error=#{error.class}")
      end
    end
  end
end
