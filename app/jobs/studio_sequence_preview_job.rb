# frozen_string_literal: true
class StudioSequencePreviewJob < ApplicationJob
  queue_as :studio
  def perform(id)
    op=StudioOperation.where(capability:Studio::Performance::Sequence::CAPABILITY).find(id);claimed=false
    op.with_lock do
      if %w[pending running].include?(op.status) && Time.iso8601(op.metadata.fetch("deadline"))<Time.current
        op.update!(status:"failed",error_message:"The sequence worker was interrupted. Retry the saved cut.",completed_at:Time.current)
      end
      return unless op.status=="pending"
      op.update!(status:"running",started_at:Time.current);claimed=true
    end
    self.class.set(wait:11.minutes).perform_later(id)
    Studio::Performance::Sequence.check!(op)
    Studio::MediaProcess.temporary_directory("sequence-review-") do |root|
      sources=op.manifest.fetch("sources");assets={};paths=[];staged={};offset=0
      clips=sources.each_with_index.map do |row,index|
        blob=op.performance_sources.blobs.find(row.fetch("blob_id"))
        path=staged[blob.id] ||= File.join(root,"source-#{blob.id}.mp4")
        blob.open { |file| FileUtils.cp(file.path,path) } unless File.exist?(path)
        paths<<path
        info=JSON.parse(run(["ffprobe","-v","error","-show_entries","format=duration:stream=codec_type","-of","json",path],root,op,timeout:30))
        duration=Float(info.fetch("format").fetch("duration"))
        raise ArgumentError,"A selected trim exceeds the real source duration" unless duration.finite? && row["out"]<=duration+0.05
        raise ArgumentError,"A source has no video track" unless info.fetch("streams").any? { |stream| stream["codec_type"]=="video" }
        audio=info["streams"].any? { |stream| stream["codec_type"]=="audio" }
        assets[index+1]=Struct.new(:id,:kind,:status,:metadata).new(index+1,"video","ready",{"duration"=>duration,"has_audio"=>audio})
        clip={"asset_id"=>index+1,"in"=>row["in"],"out"=>row["out"],"start"=>offset};offset+=row["seconds"];clip
      end
      timeline=Studio::Editing::Timeline.normalize({"width"=>320,"height"=>180,"fps"=>24,"clips"=>clips},assets:assets)
      output=File.join(root,"sequence-preview.mp4")
      run(Studio::Editing::Timeline.command(timeline,paths:paths,output:output),root,op,timeout:240)
      raise "The sequence worker did not produce a video" unless File.size?(output)
      info=JSON.parse(run(["ffprobe","-v","error","-show_entries","format=duration","-of","json",output],root,op,timeout:30))
      raise "Sequence duration verification failed" unless (Float(info.fetch("format").fetch("duration"))-offset).abs<=0.2
      blob=File.open(output,"rb") { |file| ActiveStorage::Blob.create_and_upload!(io:file,filename:"sequence-preview.mp4",content_type:"video/mp4",identify:false,metadata:LightekPwa::MediaOwnership.for(op) || {}) }
      op.with_lock do
        raise "This sequence preview is no longer active" unless op.reload.status=="running"
        Studio::Performance::Sequence.check!(op)
        artifact=op.artifacts.create!(kind:"video",filename:"sequence-preview.mp4");artifact.file.attach(blob)
        op.update!(status:"completed",completed_at:Time.current)
      end
    end
  rescue StandardError=>error
    op&.with_lock { op.update!(status:"failed",error_message:error.message.to_s.first(800),completed_at:Time.current) unless op.status=="cancelled" } if claimed
    raise
  end
  private
  def run(command,root,op,timeout:)
    if Rails.env.production?
      command=Studio::MediaProcess.container(command.map { |part| part.gsub(root,"/work") },root:root,image:Studio::NativeBlender::Runtime.image(:media),memory:Studio::Compute::Guardrails::MEDIA_MEMORY)
    end
    Studio::MediaProcess.run!(command,timeout:timeout,cancel_if:-> { op.reload.status!="running" })
  end
end
