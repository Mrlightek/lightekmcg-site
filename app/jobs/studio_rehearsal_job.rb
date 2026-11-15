# frozen_string_literal: true
class StudioRehearsalJob < ApplicationJob
  queue_as :studio
  self.enqueue_after_transaction_commit=true
  def perform(id)
    operation=StudioOperation.where(capability:Studio::Director::Rehearsal::CAPABILITY).find(id)
    claimed=false
    operation.with_lock do
      return unless operation.status=='pending'
      operation.update!(status:'running',started_at:Time.current,error_message:nil);claimed=true
    end
    actor=User.find(operation.intent.fetch('user_id'))
    Studio::Director::Rehearsal.find!(id,actor:actor)
    Studio::Gatekeeper::Client.authorize!(capability:'studio.workspace.performance.preview',subject:operation,context:{project_id:operation.studio_project_id,scene_id:operation.studio_scene_id})
    raise ArgumentError,'The source scene changed before rehearsal began' unless Studio::Director::Finishing.scene_signature(operation.studio_scene)==operation.metadata['scene_signature']
    Studio::Providers::BlenderProvider.new(operation).call
    report_artifact=operation.artifacts.find_by!(filename:'rehearsal.json')
    raise 'Rehearsal produced no playable video' unless operation.artifacts.where(kind:'video').any? { |artifact| artifact.file.attached? }
    raise 'Rehearsal report is too large' if report_artifact.file.blob.byte_size>500_000
    report=JSON.parse(report_artifact.file.download)
    raise 'Invalid rehearsal report' unless report.is_a?(Hash) && %w[ready needs_attention].include?(report['status']) && report['corrections'].is_a?(Array) && report['corrections'].size<=16
    operation.with_lock do
      return if operation.status=='cancelled'
      Studio::Director::Rehearsal.find!(id,actor:actor)
      operation.update!(status:'completed',completed_at:Time.current,metadata:operation.metadata.merge('rehearsal_report'=>report))
    end
  rescue StandardError=>error
    operation&.with_lock { operation.update!(status:'failed',completed_at:Time.current,error_message:error.message.to_s.first(2000)) unless operation.status=='cancelled' } if claimed
    raise
  end
end
