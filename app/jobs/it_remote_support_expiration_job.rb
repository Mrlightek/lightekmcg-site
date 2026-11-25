# frozen_string_literal: true

class ItRemoteSupportExpirationJob < ApplicationJob
  queue_as :default

  def perform(room_id)
    room = ItRemoteSupportSession.open.find_by(id: room_id)
    ItServices::RemoteScreenShare.expire!(room) if room
  end
end
