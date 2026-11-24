# frozen_string_literal: true

class ItRemoteSupportCaseReceiptJob < ApplicationJob
  queue_as :default

  def perform(room_id, actor_id)
    room = ItRemoteSupportSession.find_by(id: room_id)
    ItServices::RemoteSupportCaseReceipt.record!(room, actor_id) if room
  end
end
