# frozen_string_literal: true
class StudioAiGenerationJob < ApplicationJob
  queue_as :studio
  def perform(id)
    asset=StudioAsset.find(id);runtime=Studio::Ai::Runtime.new(site:DymondSite::Site.find(asset.site_id),identity:asset.metadata["ai_worker"] || {"mode"=>"local"});submit=false
    asset.with_lock do
      return if %w[ready failed].include?(asset.status)
      if asset.status=="uploaded"
        # Commit the submission claim BEFORE contacting an external process.
        # A crashed submit must be reconciled, never blindly submitted twice.
        asset.update!(status:"processing",metadata:asset.metadata.merge("ai_phase"=>"submitting","ai_started_at"=>Time.current.iso8601))
        submit=true
      elsif asset.metadata["ai_phase"]=="submitting"
        if Time.iso8601(asset.metadata.fetch("ai_started_at"))<5.minutes.ago
          asset.update!(status:"failed",error_message:"Engine submission was interrupted. Check the local engine queue before generating again.")
        else
          self.class.set(wait:1.minute).perform_later(id)
        end
        return
      end
    end
    if submit
      # Durable watchdog also reconciles a worker that dies during submission.
      self.class.set(wait:6.minutes).perform_later(id)
      begin
        prompt_id=runtime.submit(asset.metadata.fetch("ai_graph"))
        asset.update!(metadata:asset.metadata.merge("ai_prompt_id"=>prompt_id,"ai_phase"=>"generating"))
      rescue StandardError
        asset.update!(status:"failed",error_message:"The engine submission was not confirmed. Check its queue before generating again.",metadata:asset.metadata.merge("ai_phase"=>"submission_unconfirmed"))
        return
      end
    end
    if asset.metadata["ai_phase"]=="generating"
      result=runtime.result(asset.metadata.fetch("ai_prompt_id"))
      raise ArgumentError,"The local engine failed to generate this media" if result&.dig("status","status_str")=="error"
      if !result || !result.dig("status","completed")
        raise ArgumentError,"Generation exceeded one hour. Check your local worker before submitting again." if Time.iso8601(asset.metadata.fetch("ai_started_at"))<1.hour.ago
        self.class.set(wait:5.seconds).perform_later(id);return
      end
      choices=result.fetch("outputs").values.flat_map{|out|%w[images gifs audio videos gltf].flat_map{|key|Array(out[key])}}
      extensions={"image"=>%w[.png .jpg .jpeg .webp],"video"=>%w[.mp4 .webm .mov],"audio"=>%w[.wav .mp3 .flac .ogg],"glb"=>%w[.glb]}
      output=choices.find{|value|value.is_a?(Hash) && value["type"]=="output" && extensions.fetch(asset.kind).include?(File.extname(value["filename"].to_s).downcase)}
      raise ArgumentError,"This workflow produced no compatible saved output" unless output
      asset.with_lock do
        return unless asset.metadata["ai_phase"]=="generating" && asset.status=="processing"
        asset.update!(metadata:asset.metadata.merge("ai_phase"=>"preparing","ai_output"=>output,"ai_preparing_at"=>Time.current.iso8601))
      end
    elsif asset.metadata["ai_phase"]=="preparing"
      asset.with_lock do
        return if %w[ready failed].include?(asset.status)
        if Time.iso8601(asset.metadata.fetch("ai_preparing_at"))>15.minutes.ago
          self.class.set(wait:16.minutes).perform_later(id);return
        end
        asset.update!(metadata:asset.metadata.merge("ai_preparing_at"=>Time.current.iso8601))
      end
    else
      return
    end
    self.class.set(wait:16.minutes).perform_later(id)
    metadata=asset.metadata.deep_dup
    bytes=runtime.download(metadata.fetch("ai_output"))
    filename=File.basename(metadata.fetch("ai_output").fetch("filename"))
    # Upload after the claim commits: ingest must be able to open the original.
    asset.file.attach(io:StringIO.new(bytes),filename:filename,content_type:Marcel::MimeType.for(StringIO.new(bytes),name:filename))
    Studio::Assets::Ingestor.call(asset)
    asset.update!(metadata:asset.metadata.merge(metadata).except("ai_graph","ai_output","ai_preparing_at").merge("ai_phase"=>"ready"))
  rescue StandardError=>error
    asset&.reload
    if asset && asset.status=="processing" && asset.metadata["ai_phase"]=="generating" && [SystemCallError,SocketError,Timeout::Error,IOError].any?{|type|error.is_a?(type)} && Time.iso8601(asset.metadata.fetch("ai_started_at"))>1.hour.ago
      self.class.set(wait:15.seconds).perform_later(id)
    else
      asset&.update!(status:"failed",error_message:error.is_a?(ArgumentError) ? error.message.first(400) : "The local AI worker could not finish. Check worker health and retry with a new generation.")
    end
  end
end
