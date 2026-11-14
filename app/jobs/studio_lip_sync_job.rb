# frozen_string_literal: true
class StudioLipSyncJob < ApplicationJob
  queue_as :studio
  def perform(id)
    operation=StudioOperation.find(id)
    operation.with_lock do
      return unless operation.operation_type=="speech_analysis" && operation.status=="pending"
      operation.update!(status:"running",started_at:Time.current)
    end
    # A watchdog makes an interrupted analysis explicitly retryable with a new request.
    self.class.set(wait:5.minutes).perform_later(id)
    intent=operation.intent
    blob=operation.performance_sources.blobs.find(intent.fetch("audio_blob_id"))
    result=Studio::Performance::LipSync.call(blob,first:intent.fetch("source_in"),duration:intent.fetch("duration"),recognizer:intent.fetch("recognizer"),dialogue:intent.fetch("dialogue"))
    operation.with_lock do
      operation.update!(status:"completed",manifest:{"lip_sync"=>result},completed_at:Time.current) if operation.status=="running"
    end
  rescue StandardError
    operation&.update!(status:"failed",error_message:"Speech analysis could not finish. Check the speech worker, then analyze the recording again.",completed_at:Time.current)
    raise
  ensure
    if operation&.operation_type=="speech_analysis" && operation.status=="running" && operation.started_at && operation.started_at<4.minutes.ago
      operation.update!(status:"failed",error_message:"Speech analysis was interrupted. Analyze again to retry.",completed_at:Time.current)
    end
  end
end
