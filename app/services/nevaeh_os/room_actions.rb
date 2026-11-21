# frozen_string_literal: true

module NevaehOs
  module RoomActions
    INPUTS = {
      'sessions.room.status' => {'room_id'=>:id}.freeze,
      'sessions.room.invite' => {'room_id'=>:id, 'email_address'=>254}.freeze
    }.freeze

    module_function

    def authorize!(actor, values)
      room = LightekSessions::Room.find(values.fetch('room_id'))
      LightekSessions::Access.authorize!(room, actor)
      room
    rescue LightekSessions::Access::Denied
      raise ActiveRecord::RecordNotFound, 'Session room unavailable'
    end

    def perform!(actor, intent, room, values)
      url = "/sessions/#{room.key}"
      if intent == 'sessions.room.invite'
        LightekSessions::Access.invite!(room, actor, values.fetch('email_address'))
        {'room_id'=>room.id, 'invited'=>true, 'text'=>'Guest place assigned. Share the room link with your guest.',
         'links'=>[{'label'=>'Open room', 'url'=>url}]}
      else
        {'room_id'=>room.id, 'room_status'=>room.status, 'locked'=>room.locked?,
         'starts_at'=>room.starts_at.iso8601, 'ends_at'=>room.ends_at.iso8601,
         'links'=>[{'label'=>'Open room', 'url'=>url}]}
      end
    rescue LightekSessions::Access::Denied => error
      raise ArgumentError, error.message
    end
  end
end
