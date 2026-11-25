# frozen_string_literal: true

class ItRemoteSupportRecordingExpirationJob < ApplicationJob
  queue_as :default

  def perform(recording_id)
    ItRemoteSupportRecording.where(id: recording_id).where(expires_at: ..Time.current).update_all(payload: nil)
  end
end
