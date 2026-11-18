# frozen_string_literal: true

module Studio
  module Compute
    class ProceduralMovie
      SHAPES = {"cube"=>"cube", "sphere"=>"sphere", "cylinder"=>"cylinder"}.freeze
      CAMERAS = {"front"=>[0,-7,3], "angle"=>[5,-7,4], "overhead"=>[0,-0.1,8]}.freeze
      LIGHTS = {"soft"=>700, "bright"=>1250, "low"=>350}.freeze
      MOTIONS = %w[still spin slide].freeze

      def self.pools(site)
        result = []
        result << "local" if Queue.dedicated? && Queue.shared_storage?
        if ENV["STUDIO_CPU_REMOTE"] == "1" && LightekReservations::Federation::Client.config(site).present?
          result << "remote"
        end
        result << "standard" unless Queue.dedicated?
        result
      end

      def self.preview(scene:, access:, payload:)
        project = scene.studio_project
        raise ActiveRecord::RecordNotFound unless project.site_id == access.site_id

        key = payload.fetch("request_key").to_s
        raise ArgumentError, "Use a valid render request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        manifest = build(scene, payload.fetch("scene_preset"), payload.fetch("procedural_script_params"), draft: true)
        actor = access.user
        capability = "studio.workspace.blender.preview"
        operation = actor.with_lock do
          previews = StudioOperation.where(capability: capability, studio_project_id: access.projects.select(:id))
            .where("CAST(intent ->> 'user_id' AS TEXT) = ?", actor.id.to_s)
            .where("metadata ->> 'procedural_preview_key' IS NOT NULL")
          existing = previews.where("metadata ->> 'procedural_preview_key' = ?", key).first
          if existing
            unless existing.studio_scene_id == scene.id && existing.manifest == manifest
              raise ArgumentError, "This request already belongs to a different preview"
            end
            next existing
          end
          active = previews.where(status: %w[pending running]).where("created_at > ?", 5.minutes.ago)
          if active.exists? || previews.where("created_at > ?", 1.minute.ago).count >= 4
            raise ArgumentError, "Wait for your current draft before starting another preview"
          end

          preview = scene.studio_operations.create!(studio_project: project, production: scene.production,
            operation_type: "build_scene", provider: "blender", capability: capability, status: "pending",
            intent: {"user_id"=>actor.id}, manifest: manifest,
            metadata: {"draft_preview"=>true, "procedural_preview_key"=>key})
          StudioBlenderPreviewJob.perform_later(preview.id)
          preview
        end
        {operation_id: operation.id, status: operation.status}
      end

      def self.quote(scene:, actor:, site_id:, payload:)
        project = scene.studio_project
        raise ActiveRecord::RecordNotFound unless project.site_id == site_id
        key = payload.fetch("request_key").to_s
        raise ArgumentError, "Use a valid render request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        mode = payload.fetch("routing_mode")
        manifest = build(scene, payload.fetch("scene_preset"), payload.fetch("procedural_script_params"))
        scene.with_lock do
          operation = scene.studio_operations.where(capability: "studio.render.preview")
            .where("metadata ->> 'procedural_request_key' = ?",key).first
          if operation
            unless operation.intent["user_id"]==actor.id && operation.manifest==manifest && operation.metadata["cpu_routing_mode"]==mode
              raise ArgumentError, "This request already belongs to a different render"
            end
          else
            raise ArgumentError, "Choose an available render pool" unless pools(project.site).include?(mode)
            operation=scene.studio_operations.create!(studio_project:project, production:scene.production,
              operation_type:"build_scene", provider:"blender", capability:"studio.render.preview", status:"awaiting_payment",
              intent:{"user_id"=>actor.id}, manifest:manifest,metadata:{"procedural_request_key"=>key,"cpu_routing_mode"=>mode})
          end
          Studio::Billing::Quote.call(operation:operation,rail: :stripe_card) if operation.cost_quote.blank?
          {operation_id:operation.id,quote:operation.reload.cost_quote,status:operation.status}
        end
      end

      def self.build(scene, preset, options, draft: false)
        unless options.is_a?(Hash) && options.keys.sort == %w[camera lighting motion]
          raise ArgumentError, "Choose valid scene controls"
        end
        fps, frame_count = draft ? [12, 24] : [24, 120]
        shape = SHAPES.fetch(preset) { raise ArgumentError, "Choose a shape" }
        camera = CAMERAS.fetch(options.fetch("camera")) { raise ArgumentError, "Choose a camera angle" }
        light = LIGHTS.fetch(options.fetch("lighting")) { raise ArgumentError, "Choose a lighting style" }
        motion = options.fetch("motion")
        raise ArgumentError, "Choose a transform animation" unless MOTIONS.include?(motion)
        definition = {"location"=>[0,0,1], "material"=>{"color"=>[0.64,0.31,0.09,1], "roughness"=>0.4}}
        if motion != "still"
          middle = motion=="spin" ? {"rotation"=>[0,0,180]} : {"location"=>[2,0,1]}
          ending = motion=="spin" ? {"rotation"=>[0,0,360]} : {"location"=>[0,0,1]}
          beginning = motion=="spin" ? {"rotation"=>[0,0,0]} : {"location"=>[0,0,1]}
          definition["animation"]={"fps"=>fps,"frames"=>[beginning.merge("frame"=>1),middle.merge("frame"=>frame_count / 2),ending.merge("frame"=>frame_count)]}
        end
        records = [
          ["Subject",shape,definition],
          ["Floor","plane",{"scale"=>[8,8,1]}],
          ["Camera","camera",{"location"=>camera,"look_at"=>[0,0,1],"lens"=>45}],
          ["Key light","point_light",{"location"=>[3,-4,6],"energy"=>light}]
        ]
        objects=records.each_with_index.map { |(name,type,controls),i| {"id"=>i+1,"name"=>name,"type"=>type,"definition"=>controls} }
        settings=CpuProfile.settings({"compute_profile"=>CpuProfile::ID,"resolution_x"=>(draft ? 320 : 512), "resolution_y"=>(draft ? 180 : 288),
          "samples"=>(draft ? 2 : Guardrails::CPU_SAMPLES), "fps"=>fps, "frame_start"=>1, "frame_current"=>1,
          "frame_end"=>frame_count, "active_camera_object_id"=>3})
        Federation::Contract.validate!({"schema_version"=>"1.0","project"=>{"id"=>scene.studio_project_id,"name"=>scene.studio_project.name},
          "scene"=>{"id"=>scene.id,"name"=>scene.name,"settings"=>settings,"objects"=>objects},
          "outputs"=>{"animation"=>true,"blend"=>!draft}})
      end
    end
  end
end
