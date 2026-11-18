# frozen_string_literal: true
class StudioEpisodeAssemblyJob < ApplicationJob
  queue_as :studio
  self.enqueue_after_transaction_commit = true
  def perform(id)
    @operation_id = id
    operation = StudioOperation.find(id)
    claimed = false
    operation.with_lock do
      return unless operation.capability=='studio.direct.assemble' && operation.status=='pending'
      operation.update!(status:'running',started_at:Time.current,error_message:nil)
      claimed = true
    end
    actor = User.find(operation.intent.fetch('user_id'))
    Studio::Director::Producer.find!(operation.production_id,actor:actor)
    Studio::Director::Finishing.verify_sources!(operation)
    Studio::MediaProcess.temporary_directory('episode-master-') do |root|
      sources = operation.manifest.fetch('sources')
      sources.each_with_index do |row,index|
        blob = operation.performance_sources.find { |item| item.blob_id==row.fetch('blob_id') }&.blob || raise('The pinned scene export is unavailable')
        input = File.join(root,"source-#{index}")
        File.open(input,'wb') { |file| blob.download { |chunk| file.write(chunk) } }
        info = probe(input,root)
        duration = Float(info.fetch('format').fetch('duration'))
        raise ArgumentError, 'Each export must cover its full scene duration' unless duration.finite? && (duration-row.fetch('seconds')).abs<=0.15
        audio = info.fetch('streams').any? { |stream| stream['codec_type']=='audio' }
        command = ['ffmpeg','-v','error','-y','-threads','1','-i',input]
        command += ['-f','lavfi','-i','anullsrc=channel_layout=stereo:sample_rate=48000'] unless audio
        command += ['-map','0:v:0','-map',audio ? '0:a:0' : '1:a:0','-vf','scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=24','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-threads','1','-c:a','aac','-ar','48000','-ac','2','-af','apad','-t',row.fetch('seconds').to_s,File.join(root,"segment-#{index}.mp4")]
        run(command,root,timeout:1800)
      end
      File.write(File.join(root,'segments.txt'),sources.each_index.map { |index| "file 'segment-#{index}.mp4'" }.join("\n"))
      output = File.join(root,'episode.mp4')
      run(['ffmpeg','-v','error','-y','-f','concat','-safe','1','-i',File.join(root,'segments.txt'),'-c','copy','-movflags','+faststart',output],root,timeout:1800)
      info = probe(output,root)
      duration = Float(info.fetch('format').fetch('duration'))
      raise 'Episode runtime verification failed' unless (duration-sources.sum { |row| row['seconds'] }).abs<=0.5
      blob = File.open(output,'rb') { |file| ActiveStorage::Blob.create_and_upload!(io:file,filename:'episode.mp4',content_type:'video/mp4',identify:false,metadata:LightekPwa::MediaOwnership.for(operation) || {}) }
      operation.production.with_lock do
        scenes = sources.map { |row| operation.production.studio_scenes.find(row['scene_id']) }.sort_by(&:id)
        scenes.each(&:lock!)
        operation.lock!
        return if operation.status=='cancelled'
        Studio::Director::Producer.find!(operation.production_id,actor:actor)
        Studio::Director::Finishing.verify_sources!(operation)
        artifact = operation.artifacts.create!(kind:'video',filename:'episode.mp4')
        artifact.file.attach(blob)
        operation.update!(status:'completed',completed_at:Time.current,manifest:operation.manifest.merge('artifact_id'=>artifact.id,'duration'=>duration))
      end
    end
  rescue StandardError => error
    operation&.with_lock { operation.update!(status:'failed',completed_at:Time.current,error_message:error.message.to_s.first(2000)) unless operation.status=='cancelled' } if claimed
    raise
  end
  private
  def run(command,root,timeout:)
    command = Studio::MediaProcess.container(command.map { |part| part.gsub(root,'/work') },root:root,image:Studio::NativeBlender::Runtime.image(:media)) if Rails.env.production?
    Studio::MediaProcess.run!(command,timeout:timeout,cancel_if:-> { StudioOperation.find(@operation_id).status=='cancelled' })
  end
  def probe(path,root)
    JSON.parse(run(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_type','-of','json',path],root,timeout:30))
  end
end
