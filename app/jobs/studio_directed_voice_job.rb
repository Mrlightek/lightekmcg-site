# frozen_string_literal: true
class StudioDirectedVoiceJob < ApplicationJob
  queue_as :studio
  self.enqueue_after_transaction_commit = true
  def perform(id)
    operation = StudioOperation.find(id)
    operation.with_lock do
      return unless operation.capability == 'studio.direct.voice' && operation.status == 'pending'
      operation.update!(status: 'running', started_at: Time.current, error_message: nil)
    end
    actor = User.find(operation.intent.fetch('user_id'))
    Studio::Director::Producer.find!(operation.production_id, actor: actor)
    scene = Studio::PwaAccess.new('user_id'=>actor.id,'site_id'=>operation.studio_project.site_id).scene!(operation.studio_scene_id)
    cues = operation.manifest.fetch('dialogue')
    assets = cues.each_with_index.map { |line,index| Studio::Director::Voice.asset!(operation, actor, line, index) }
    cursor=0.0
    cues=cues.zip(assets).map do |line,asset|
      cue=line.merge('start'=>line['auto_start'] ? cursor : line.fetch('start'))
      cursor=[cursor,cue['start']+asset.metadata.fetch('duration')].max
      cue
    end
    scene.with_lock do
      operation.reload
      return if operation.status == 'cancelled'
      Studio::Director::Producer.authorize!(actor, operation.studio_project.site)
      raise ActiveRecord::StaleObjectError.new(scene,'voice direction') unless scene.lock_version == operation.metadata.fetch('scene_version')
      timeline = scene.settings.fetch('timeline', Studio::Editing::Timeline.format('landscape').merge('clips'=>[])).deep_dup
      timeline['clips'] ||= []; timeline['titles'] ||= []; timeline['tracks'] ||= []
      track = timeline['tracks'].find { |item| item['name']=='Dialogue' }
      track ||= {'id'=>(0..15).find { |number| timeline['tracks'].none? { |item| item['id']==number } }, 'name'=>'Dialogue'}
      raise ArgumentError, 'Free a track for the dialogue' unless track['id']
      timeline['tracks'] << track unless timeline['tracks'].include?(track)
      fps = scene.settings.fetch('fps',24).to_f / scene.settings.fetch('fps_base',1)
      seconds = scene.settings.fetch('frame_end',1).to_f/fps
      cues.zip(assets).each do |cue,asset|
        ending = cue['start']+asset.metadata.fetch('duration')
        raise ArgumentError, 'The spoken take exceeds this scene; shorten the line or extend the scene' if ending > seconds+0.05
        timeline['clips'] << {'asset_id'=>asset.id,'start'=>cue['start'],'out'=>asset.metadata['duration'],'track'=>track['id']}
        text = "#{cue['speaker']}: #{cue['text']}".scan(/\S.{0,51}(?=\s|$)|\S{1,52}/).map(&:strip).join("\n")
        timeline['titles'] << {'text'=>text,'start'=>cue['start'],'end'=>ending,'x'=>timeline.fetch('width')*0.08,'y'=>timeline.fetch('height')*0.65,'size'=>timeline.fetch('height')*0.028}
      end
      access = Studio::PwaAccess.new('user_id'=>actor.id,'site_id'=>operation.studio_project.site_id)
      owned = StudioAsset.for_actor(access).where(site_id: access.site_id, id: timeline['clips'].map { |clip| clip['asset_id'] }).index_by(&:id)
      normalized = Studio::Editing::Timeline.normalize(timeline, assets: owned)
      scene.update!(settings: scene.settings.merge('timeline'=>normalized,'voice_direction'=>{'operation_id'=>operation.id,'asset_ids'=>assets.map(&:id),'synthetic'=>true}))
      operation.update!(status: 'completed', completed_at: Time.current, manifest: operation.manifest.merge('dialogue'=>cues,'asset_ids'=>assets.map(&:id)))
    end
  rescue StandardError => error
    operation&.with_lock do
      operation.update!(status: 'failed', completed_at: Time.current, error_message: error.message.to_s.first(2000)) unless operation.status == 'cancelled'
    end
    raise
  end
end
