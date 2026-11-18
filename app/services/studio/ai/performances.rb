# frozen_string_literal: true
module Studio
  module Ai
    class Performances
      RECIPES = {
        "musetalk" => {name:"MuseTalk", action:"Lip sync a performance", source:%w[image video], driver:"audio"},
        "liveportrait" => {name:"LivePortrait", action:"Animate a portrait", source:%w[image], driver:"video"},
        "facefusion" => {name:"FaceFusion", action:"Change the actor’s face", source:%w[image], driver:"video"}
      }.freeze
      MIME_EXTENSIONS = {
        "image/jpeg"=>".jpg", "image/png"=>".png", "image/webp"=>".webp",
        "video/mp4"=>".mp4", "video/quicktime"=>".mov", "video/webm"=>".webm",
        "audio/wav"=>".wav", "audio/x-wav"=>".wav", "audio/mpeg"=>".mp3", "audio/flac"=>".flac",
        "audio/mp4"=>".m4a", "audio/ogg"=>".ogg", "audio/webm"=>".webm", "audio/aac"=>".aac"
      }.freeze
      LIMIT = 50.megabytes
      RUN_TIMEOUT = Compute::Guardrails::PERFORMANCE_TIMEOUT.seconds
      QUEUE_TIMEOUT = 1.hour
      RECOVERY_AFTER = RUN_TIMEOUT + 5.minutes

      def self.image(recipe)
        value=ENV["STUDIO_#{recipe.upcase}_CPU_IMAGE"].to_s
        value if value.match?(/\A[a-z0-9][a-z0-9.\/:_-]*@sha256:[a-f0-9]{64}\z/)
      end

      def self.inventory
        available = Compute::Queue.dedicated? && Compute::Queue.shared_storage?
        RECIPES.map { |id, entry| entry.merge(id: id, configured: available && image(id).present?) }
      end

      def self.start(access:,payload:)
        scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        id=payload.fetch("recipe")
        recipe=RECIPES.fetch(id)
        key=payload.fetch("request_key").to_s
        raise ArgumentError,"Invalid performance request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        attrs=%w[input_asset_id driver_asset_id].to_h do |field|
          value=payload.fetch(field,"").to_s
          raise ArgumentError,"Choose both source files" unless value.match?(/\A[1-9]\d{0,17}\z/)
          [field,Integer(value)]
        end
        title=payload.fetch("prompt",recipe[:action]).to_s.strip
        raise ArgumentError,"Use a title of 1–120 characters" unless title.length.between?(1,120)
        intent=attrs.merge("scene_id"=>scene.id,"prompt"=>title,"recipe"=>id)
        asset=access.user.with_lock do
          existing=StudioAsset.find_by(owner:access.user,request_key:key)
          if existing
            raise ArgumentError,"This request key belongs to another generation" unless existing.site_id==access.site_id && existing.metadata["ai_intent"]==intent
            next existing
          end
          queue = worker_queue
          worker_image = image(id) || raise(ArgumentError, "This CPU performance tool is unavailable.")
          pending=StudioAsset.where(owner:access.user,status:%w[uploaded processing]).where("metadata ->> 'ai_intent' IS NOT NULL").count
          raise ArgumentError,"Wait for your current generations to finish" if pending>=2
          scope=StudioAsset.for_actor(access).where(site_id:access.site_id,status:"ready")
          source=scope.find(attrs.fetch("input_asset_id"))
          driver=scope.find(attrs.fetch("driver_asset_id"))
          created=StudioAsset.create!(owner:access.user,site_id:access.site_id,studio_project:scene.studio_project,
            name:title,kind:"video",status:"uploaded",request_key:key,
            metadata:{"ai_intent"=>intent,"ai_phase"=>"queued","ai_performance_image"=>worker_image})
          created.ai_input.attach(validate(source,recipe[:source]))
          created.performance_driver.attach(validate(driver,[recipe[:driver]]))
          StudioAiGenerationJob.set(queue: queue).perform_later(created.id)
          StudioAiGenerationJob.set(wait: QUEUE_TIMEOUT).perform_later(created.id, true)
          created
        end
        Generation.receipt(asset)
      end

      def self.validate(asset,kinds)
        raise ArgumentError,"Choose a compatible prepared library asset" unless kinds.include?(asset.kind) && asset.proxy.attached?
        blob=asset.proxy.blob
        raise ArgumentError,"Choose a supported media file up to 50 MB" unless MIME_EXTENSIONS.key?(blob.content_type) && blob.byte_size.between?(1,LIMIT)
        if asset.kind=="image"
          InputImage.validate!(asset)
        elsif !asset.metadata["duration"].to_f.between?(0.1,Compute::Guardrails::PERFORMANCE_SECONDS)
          raise ArgumentError,"Use a recording or video between 0.1 and 15 seconds"
        end
        blob
      end

      def self.worker_queue
        raise ArgumentError, "The CPU performance worker pool is unavailable." unless Compute::Queue.dedicated?
        Compute::Queue.dedicated_name
      end

      def self.reconcile(asset)
        asset.with_lock do
          if asset.status == "uploaded" && asset.created_at <= QUEUE_TIMEOUT.ago
            asset.update!(status: "failed", error_message: "The CPU worker did not pick up this clip. Try again later.",
              metadata: asset.metadata.merge("ai_phase" => "failed"))
          elsif asset.status == "processing" && asset.metadata["ai_phase"] == "performing" &&
                Time.iso8601(asset.metadata.fetch("ai_started_at")) <= RECOVERY_AFTER.ago
            asset.update!(status: "failed", error_message: "The CPU worker stopped before saving your clip. Try again.",
              metadata: asset.metadata.merge("ai_phase" => "failed"))
          end
        end
      end

      def self.run(asset)
        return unless asset.status == "uploaded"

        queue = worker_queue
        unless Compute::Queue.worker?
          StudioAiGenerationJob.set(queue: queue).perform_later(asset.id)
          return
        end

        asset.with_lock do
          return unless asset.status == "uploaded"
          return if asset.created_at <= QUEUE_TIMEOUT.ago
          asset.update!(status: "processing", metadata: asset.metadata.merge(
            "ai_phase" => "performing", "ai_started_at" => Time.current.iso8601))
        end
        StudioAiGenerationJob.set(wait: RECOVERY_AFTER).perform_later(asset.id, true)
        recipe = asset.metadata.dig("ai_intent", "recipe")
        worker_image = asset.metadata.fetch("ai_performance_image")
        unless image(recipe) == worker_image
          raise ArgumentError, "The CPU performance worker configuration changed. Submit again."
        end
        metadata=asset.metadata
        MediaProcess.temporary_directory("studio-performance") do |root|
          sources={"source"=>asset.ai_input.blob,"driver"=>asset.performance_driver.blob}
          paths=sources.map do |slot,blob|
            filename=slot+MIME_EXTENSIONS.fetch(blob.content_type)
            blob.open { |file| FileUtils.cp(file.path,File.join(root,filename)) }
            "/work/#{filename}"
          end
          FileUtils.cp(Rails.root.join("lib/scripts/studio_performance_worker.py"),root)
          command=MediaProcess.container(["python","/work/studio_performance_worker.py",recipe,*paths],root:root,image:worker_image,
            memory: Compute::Guardrails::PERFORMANCE_MEMORY, pull: false)
          MediaProcess.run!(command,timeout:RUN_TIMEOUT)
          file=File.join(root,"performance.mp4")
          raise ArgumentError,"Performance worker did not save a usable video" unless File.file?(file) && !File.symlink?(file) && File.size(file).between?(1,250.megabytes)
          asset.reload
          return unless asset.status == "processing"
          File.open(file, "rb") { |io| asset.file.attach(io: io, filename: "performance.mp4", content_type: "video/mp4") }
        end
        Studio::Assets::Ingestor.call(asset)
        asset.update!(metadata: asset.metadata.merge(metadata).except("ai_performance_image", "ai_started_at").merge("ai_phase" => "ready"))
      rescue StandardError => error
        Rails.logger.warn("Studio CPU performance asset #{asset.id}: #{error.class}: #{error.message.to_s.first(1000)}")
        asset.update!(status: "failed", metadata: asset.metadata.merge("ai_phase" => "failed"),
          error_message: error.is_a?(ArgumentError) ? error.message.first(400) : "The CPU worker could not finish your clip. Try again or contact Studio support.")
      end
    end
  end
end
