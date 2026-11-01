# frozen_string_literal: true
module Studio
  module Workers
    class Workspace
      ACTIONS = %w[scene_save project_delete template_save template_use render_quote render_checkout operations_list artifact_publish director_execute visual_save asset_import assets_list timeline_save timeline_quote asset_place asset_use asset_publish asset_retry library_apply blender_template_use blender_camera_create blender_camera_save blender_demo_import blender_prepare blender_preset_use].freeze
      def self.perform(action, payload = {}) = new(action, payload).perform
      def initialize(action, payload)
        @action = action.to_s
        @payload = payload.to_h.deep_stringify_keys
        @access = Studio::PwaAccess.new(@payload)
      end
      def perform
        LightekPwa::Policy.new(user: @access.user, site: DymondSite::Site.find(@access.site_id)).authorize!("studio") if @access.site_id
        raise ArgumentError, "Unsupported Studio workspace action" unless ACTIONS.include?(@action)
        public_send(@action)
      end

      def scene_save
        scene = @access.scene!(@payload.fetch("scene_id"))
        workspace = @payload.fetch("workspace").to_h.deep_stringify_keys
        raise ArgumentError, "Workspace is too large" if workspace.to_json.bytesize > 250_000
        # Optimistic locking prevents silently overwriting a second open editor.
        scene.lock_version = Integer(@payload.fetch("lock_version"))
        scene.settings = scene.settings.to_h.merge("workspace" => workspace.slice("story", "visual", "delivery", "layout", "presets"))
        scene.save!
        { scene_id: scene.id, lock_version: scene.lock_version, workspace: scene.settings["workspace"] }
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError, "This scene changed in another editor. Refresh before saving again."
      end

      def visual_save
        scene = @access.scene!(@payload.fetch("scene_id"))
        scene.lock_version = Integer(@payload.fetch("lock_version"))
        settings = @payload.fetch("render_settings").to_h
        engine = settings.fetch("render_engine")
        raise ArgumentError, "Unsupported render engine" unless %w[BLENDER_EEVEE_NEXT CYCLES].include?(engine)
        width, height = Integer(settings.fetch("resolution_x")), Integer(settings.fetch("resolution_y"))
        raise ArgumentError, "Resolution must be between 64 and 4096 pixels" unless width.between?(64, 4096) && height.between?(64, 4096)
        scene.transaction do
          scene.settings = scene.settings.to_h.merge("render_engine" => engine, "resolution_x" => width, "resolution_y" => height,
            "transparent_background" => ActiveModel::Type::Boolean.new.cast(settings["transparent_background"]))
          timeline={}
          %w[frame_start frame_end frame_current fps samples].each { |key| timeline[key]=Integer(settings[key]) if settings.key?(key) }
          raise ArgumentError,"Use an FPS from 1 to 120" if timeline["fps"] && !timeline["fps"].between?(1,120)
          raise ArgumentError,"Use 1–256 preview samples" if timeline["samples"] && !timeline["samples"].between?(1,256)
          first=timeline.fetch("frame_start",scene.settings.fetch("frame_start",1));last=timeline.fetch("frame_end",scene.settings.fetch("frame_end",250))
          frame=timeline.fetch("frame_current",scene.settings.fetch("frame_current",first))
          raise ArgumentError,"Choose an ordered Blender frame range and a frame within it" unless first.between?(-1000000,1000000) && last.between?(first,1000000) && frame.between?(first,last)
          scene.settings=scene.settings.merge(timeline)
          if @payload["object_id"].present?
            object = scene.scene_objects.find(@payload["object_id"])
            properties = @payload.fetch("properties", {}).to_h
            definition = object.definition.to_h.deep_dup
            if object.object_type == "camera"
              definition["lens"] = bounded_number(properties.fetch("lens"), 2, 250)
            elsif object.object_type.end_with?("_light")
              definition["energy"] = bounded_number(properties.fetch("energy"), 0, 1_000_000)
              definition["color"] = color(properties.fetch("color"), 3)
              definition["size"] = bounded_number(properties.fetch("size", 5), 0.001, 1000) if object.object_type == "area_light"
            else
              definition["material"] = definition.fetch("material", {}).merge("color" => color(properties.fetch("color"), 4))
            end
            object.update!(definition: definition)
          end
          scene.save!
        end
        { scene_id: scene.id, lock_version: scene.lock_version }
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError, "This scene changed in another editor. Refresh before saving again."
      end

      def project_delete
        project = @access.projects.find(@payload.fetch("project_id"))
        project.destroy!
        { deleted_project_id: project.id }
      end

      def template_save
        source = @access.projects.find(@payload.fetch("project_id"))
        copy_project(source, template: true)
      end

      def template_use
        source = @access.projects.where(is_template: true).find(@payload.fetch("project_id"))
        copy_project(source, template: false)
      end

      def render_quote
        scene = @access.scene!(@payload.fetch("scene_id"))
        operation = scene.studio_operations.create!(studio_project: scene.studio_project, production: scene.production,
          operation_type: "build_scene", provider: "blender", capability: "studio.render.preview", status: "awaiting_payment", intent: {"user_id"=>@access.user.id},
          manifest: Blender::ManifestBuilder.new(scene).call)
        Studio::Billing::Quote.call(operation: operation, rail: :stripe_card)
        { operation_id: operation.id, quote: operation.reload.cost_quote, status: operation.status }
      end

      def render_checkout
        operation = StudioOperation.where(studio_project_id: @access.projects.select(:id)).find(@payload.fetch("operation_id"))
        raise ArgumentError, "Render is not awaiting payment" unless operation.status == "awaiting_payment"
        # Origin is injected by the controller; the client cannot choose redirects.
        return_url = "#{@payload.fetch('origin')}/lightek/index.html#/studio/#{operation.studio_scene_id}"
        checkout = Studio::Billing::Checkout.call(operation: operation, payer: @access.user, success_url: return_url, cancel_url: return_url)
        { checkout_url: checkout.respond_to?(:url) ? checkout.url : checkout.fetch(:url) }
      end

      def artifact_publish
        project = @access.projects.find(@payload.fetch("project_id"))
        publication = nil
        project.with_lock do
          key = @payload.fetch("request_key").to_s
          raise ArgumentError, "Request key required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
          platform=@payload.fetch("platform","lightek_social")
          raise ArgumentError,"Choose a native publishing destination" unless %w[lightek_social lightek_streaming octavia].include?(platform)
          metadata = { "user_id" => @access.user.id, "site_id" => @access.site_id, "request_key" => key,
            "audience" => @payload.fetch("audience","everyone"), "title" => @payload["title"], "content" => @payload["content"], "community_slug" => @payload["community_slug"] }
          publication = project.studio_publications.find_by(request_key: key)
          unless publication
            operation = project.studio_operations.where(status: "completed").joins(:artifacts).where(artifacts: { id: @payload.fetch("artifact_id") }).first!
            artifact = operation.artifacts.find(@payload.fetch("artifact_id"))
            metadata["sources"] = Array(operation.manifest["credits"])
            raise ArgumentError,"OTT publishing requires a video master" if platform!="lightek_social" && !artifact.file.blob.content_type.start_with?("video/")
            time = @payload["publish_at"].present? ? Time.iso8601(@payload["publish_at"]) : nil
            publication = project.studio_publications.create!(artifact: artifact, production: operation.production,
              platform: platform, request_key: key, status: time&.future? ? "scheduled" : "draft", scheduled_at: time,
              metadata: metadata)
          end
        end
        StudioPublicationDispatchJob.perform_later(publication.id)
        { publication_id: publication.id, status: publication.status }
      end

      def timeline_save
        scene=@access.scene!(@payload.fetch("scene_id"))
        raw=@payload.fetch("timeline").to_h.deep_stringify_keys
        ids=Array(raw["clips"]).map{|c|Integer(c.fetch("asset_id"))}
        assets=StudioAsset.for_actor(@access).where(id:ids).index_by(&:id)
        timeline=Studio::Editing::Timeline.normalize(raw,assets:assets)
        scene.lock_version=Integer(@payload.fetch("lock_version"))
        scene.update!(settings:scene.settings.to_h.merge("timeline"=>timeline))
        {timeline:timeline,scene_id:scene.id,lock_version:scene.lock_version}
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed in another editor. Refresh before saving."
      end

      def timeline_quote
        scene=@access.scene!(@payload.fetch("scene_id"))
        timeline=scene.settings.fetch("timeline")
        assets=StudioAsset.for_actor(@access).where(id:timeline.fetch("clips").map{|c|c.fetch("asset_id")}).index_by(&:id)
        timeline=Studio::Editing::Timeline.normalize(timeline,assets:assets)
        operation=scene.studio_operations.create!(studio_project:scene.studio_project,production:scene.production,operation_type:"edit_media",provider:"ffmpeg",capability:"studio.workspace.timeline.quote",status:"awaiting_payment",intent:{"user_id"=>@access.user.id},manifest:{"timeline"=>timeline})
        Studio::Billing::Quote.call(operation:operation,rail: :stripe_card)
        {operation_id:operation.id,quote:operation.reload.cost_quote,status:operation.status}
      end

      def asset_place
        scene=@access.scene!(@payload.fetch("scene_id"))
        asset=StudioAsset.for_actor(@access).where(status:"ready",kind:%w[blend glb]).find(@payload.fetch("asset_id"))
        category=@payload.fetch("category","prop")
        raise ArgumentError,"Choose a supported production role" unless %w[character environment prop vehicle architecture geometry].include?(category)
        object=scene.scene_objects.create!(name:asset.name,object_type:"imported_asset",position:scene.scene_objects.maximum(:position).to_i+1,
          definition:{"asset_id"=>asset.id,"category"=>category,"asset_proxy_url"=>"/api/lightek/pwa/assets/#{asset.id}/proxy","location"=>[0,0,0],"rotation"=>[0,0,0],"scale"=>[1,1,1]})
        {scene_id:scene.id,object_id:object.id}
      end

      def assets_list
        scope=StudioAsset.for_actor(@access).order(id: :desc)
        scope=scope.where("id < ?",Integer(@payload["before"])) if @payload["before"].present?
        records=scope.limit(101).to_a
        more=records.length>100
        records=records.first(100)
        { media_presets: Studio::NativeBlender::MediaPresets.items, builtins: Studio::Library::Catalog.items, camera_presets: Studio::NativeBlender::CameraSettings.presets, blender_demos: Studio::NativeBlender::DemoCatalog.items, next_before: more ? records.last.id : nil, assets: records.map { |asset|
          { id:asset.id,name:asset.name,kind:asset.kind,status:asset.status,error:asset.error_message,metadata:asset.metadata,
            url:asset.file.attached? ? "/api/lightek/pwa/assets/#{asset.id}/original" : nil,bundle_url:asset.bundle.attached? ? "/api/lightek/pwa/assets/#{asset.id}/bundle" : nil,native_url:asset.native.attached? ? "/api/lightek/pwa/assets/#{asset.id}/native" : nil,proxy_url:asset.proxy.attached? ? "/api/lightek/pwa/assets/#{asset.id}/proxy" : nil,
            thumbnail_url:asset.thumbnail.attached? ? "/api/lightek/pwa/assets/#{asset.id}/thumbnail" : nil } } }
      end

      def blender_template_use
        Studio::NativeBlender::NativeTemplate.call(access:@access,payload:@payload)
      end

      def blender_preset_use
        Studio::NativeBlender::PresetUse.call(access:@access,payload:@payload)
      end

      def blender_prepare
        asset=StudioAsset.for_actor(@access).where(kind:"blend").find(@payload.fetch("asset_id"))
        asset.with_lock do
          raise ArgumentError,"This Blender import is already processing" if %w[uploaded processing].include?(asset.status)
          asset.update!(status:"uploaded",error_message:nil)
        end
        StudioAssetIngestJob.perform_later(asset.id)
        {asset_id:asset.id,status:asset.status}
      end

      def blender_demo_import
        demo=Studio::NativeBlender::DemoCatalog.fetch(@payload.fetch("demo_key"))
        asset=nil
        @access.user.with_lock do
          asset=StudioAsset.find_or_initialize_by(owner_id:@access.user.id,request_key:"blender-demo-#{@access.site_id}-#{demo.fetch('key')}")
          unless asset.persisted?
            asset.assign_attributes(site_id:@access.site_id,name:demo.fetch("name"),kind:"blend",status:"uploaded",metadata:{"demo_key"=>demo["key"],"source"=>demo})
            asset.save!
          end
          asset.update!(status:"uploaded",error_message:nil) if asset.status=="failed"
        end
        StudioBlenderDemoImportJob.perform_later(asset.id) if asset.status=="uploaded"
        {asset_id:asset.id,status:asset.status}
      end

      def blender_camera_create
        scene=@access.scene!(@payload.fetch("scene_id"))
        key=@payload.fetch("request_key").to_s
        raise ArgumentError,"A camera request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        settings=Studio::NativeBlender::CameraSettings.preset(@payload.fetch("preset"))
        result=nil
        scene.with_lock do
          journal=scene.settings.fetch("library_requests",{})
          return journal[key] if journal[key]
          scene.lock_version=Integer(@payload.fetch("lock_version"))
          object=scene.scene_objects.create!(name:@payload["name"].presence || Studio::NativeBlender::CameraSettings::PRESETS.fetch(@payload["preset"]).first,object_type:"camera",position:scene.scene_objects.maximum(:position).to_i+1,
            definition:settings.merge("location"=>[6,-8,4],"rotation"=>[72,0,0],"scale"=>[1,1,1],"look_at"=>[0,0,1.5]))
          result={"scene_id"=>scene.id,"object_id"=>object.id,"lock_version"=>scene.lock_version+1}
          scene.settings=scene.settings.merge("active_camera_object_id"=>object.id,"active_camera"=>object.name,"library_requests"=>journal.to_a.last(99).to_h.merge(key=>result))
          scene.settings=scene.settings.merge("render_engine"=>"CYCLES") if settings["camera_type"]=="PANO"
          scene.save!
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before adding a camera."
      end

      def blender_camera_save
        scene=@access.scene!(@payload.fetch("scene_id"))
        result=nil
        scene.with_lock do
          scene.lock_version=Integer(@payload.fetch("lock_version"))
          camera=scene.scene_objects.where(object_type:"camera").find(@payload.fetch("object_id"))
          values=Studio::NativeBlender::CameraSettings.normalize(@payload.fetch("properties"),base:camera.definition)
          camera.update!(definition:camera.definition.merge(values))
          if ActiveModel::Type::Boolean.new.cast(@payload["active"])
            scene.settings=scene.settings.merge("active_camera_object_id"=>camera.id,"active_camera"=>camera.definition["blender_object_name"].presence || camera.name)
            scene.settings=scene.settings.merge("render_engine"=>"CYCLES") if values["camera_type"]=="PANO"
          end
          scene.settings=scene.settings.merge("blender_camera_revision"=>scene.settings.fetch("blender_camera_revision",0).to_i+1)
          scene.save!
          result={scene_id:scene.id,object_id:camera.id,lock_version:scene.lock_version}
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before saving the camera."
      end

      def library_apply
        Studio::Library::Apply.call(access: @access, payload: @payload)
      end

      def asset_retry
        asset=StudioAsset.for_actor(@access).find(@payload.fetch("asset_id"))
        asset.with_lock do
          raise ArgumentError,"Only failed imports can be retried" unless asset.status=="failed"
          asset.update!(status:"uploaded",error_message:nil)
        end
        (asset.metadata["demo_key"] ? StudioBlenderDemoImportJob : StudioAssetIngestJob).perform_later(asset.id)
        {asset_id:asset.id,status:asset.status}
      end

      def asset_use
        scene=@access.scene!(@payload.fetch("scene_id"))
        asset=StudioAsset.for_actor(@access).where(status:"ready",kind:%w[image audio video]).find(@payload.fetch("asset_id"))
        key=@payload.fetch("request_key").to_s
        raise ArgumentError,"A library request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        result=nil
        scene.with_lock do
          journal=scene.settings.fetch("library_requests",{})
          return journal[key] if journal[key]
          scene.lock_version=Integer(@payload.fetch("lock_version"))
          timeline=scene.settings.fetch("timeline",{"output"=>"video","width"=>1280,"height"=>720,"clips"=>[]}).deep_dup
          placement=@payload.fetch("placement","append")
          raise ArgumentError,"Choose append or overlay placement" unless %w[append overlay].include?(placement)
          ending=timeline["clips"].map { |clip| clip.fetch("start",0)+clip.fetch("out")-clip.fetch("in",0) }.max || 0
          duration=asset.kind=="image" ? 5 : [asset.metadata["duration"].to_f,600].min
          raise ArgumentError,"This media has no usable duration. Retry its import." unless duration>0
          timeline["clips"]<<{"asset_id"=>asset.id,"in"=>0,"out"=>duration,"start"=>placement=="overlay" ? 0 : ending,
            "track"=>placement=="overlay" ? timeline["clips"].map { |clip| clip.fetch("track",0) }.max.to_i+1 : 0,"gain"=>1}
          assets=StudioAsset.for_actor(@access).where(id:timeline["clips"].map { |clip| clip["asset_id"] }).index_by(&:id)
          normalized=Studio::Editing::Timeline.normalize(timeline,assets:assets)
          result={"scene_id"=>scene.id,"lock_version"=>scene.lock_version+1,"timeline"=>normalized}
          # Retain only the receipt, not a duplicate copy of the timeline per click.
          receipt=result.except("timeline")
          scene.settings=scene.settings.merge("timeline"=>normalized,"library_requests"=>journal.to_a.last(99).to_h.merge(key=>receipt))
          scene.save!
        end
        result
      rescue ActiveRecord::StaleObjectError
        raise ArgumentError,"The scene changed. Refresh before adding media."
      end

      def asset_publish
        scene=@access.scene!(@payload.fetch("scene_id"))
        asset=StudioAsset.for_actor(@access).where(status:"ready",kind:%w[image audio video]).find(@payload.fetch("asset_id"))
        source=asset.proxy.attached? ? asset.proxy.blob : asset.file.blob
        platform=@payload.fetch("platform","lightek_social")
        if platform!="lightek_social" && source.content_type!="video/mp4"
          raise ArgumentError,"OTT needs an MP4 video master. Add this asset to a timeline and export it first."
        end
        project=scene.studio_project
        artifact=nil
        project.with_lock do
          operation=project.studio_operations.where(operation_type:"asset_source",studio_scene_id:scene.id)
            .where("CAST(metadata ->> 'asset_id' AS TEXT) = ?",asset.id.to_s).first
          unless operation
            operation=project.studio_operations.create!(studio_scene:scene,production:scene.production,operation_type:"asset_source",provider:"library",
              capability:"studio.workspace.asset.publish",status:"completed",intent:{"user_id"=>@access.user.id},metadata:{"asset_id"=>asset.id})
            artifact=operation.artifacts.create!(kind:asset.kind,filename:source.filename.to_s)
            artifact.file.attach(source)
          end
          artifact||=operation.artifacts.first!
        end
        @payload=@payload.merge("project_id"=>project.id,"artifact_id"=>artifact.id,"title"=>@payload["title"].presence || asset.name)
        artifact_publish
      end

      def asset_import
        asset = nil
        @access.user.with_lock do
          key = @payload.fetch("request_key").to_s
          raise ArgumentError,"Invalid import request key" unless key.match?(/\A[a-zA-Z0-9-]{16,100}\z/)
          asset = StudioAsset.where(owner_id:@access.user.id,site_id:@access.site_id).find_by(request_key:key)
          unless asset
            blob=ActiveStorage::Blob.find_signed!(@payload.fetch("signed_id"))
            raise ArgumentError,"Upload belongs to another account" unless blob.metadata["lightek_user_id"]==@access.user.id && blob.metadata["lightek_site_id"]==@access.site_id
            kind=blob.metadata["studio_kind"] || {"image"=>"image","video"=>"video","audio"=>"audio"}[blob.content_type.to_s.split('/').first]
            raise ArgumentError,"Unsupported asset type" unless %w[blend glb image audio video].include?(kind)
            asset=StudioAsset.new(owner:@access.user,site_id:@access.site_id,name:@payload.fetch("name",blob.filename.to_s),kind:kind,request_key:key)
            asset.file.attach(blob)
            asset.save!
          end
        end
        StudioAssetIngestJob.perform_later(asset.id) unless asset.status=="ready"
        { asset_id:asset.id,status:asset.status }
      end

      def director_execute
        scene = @access.scene!(@payload.fetch("scene_id"))
        instruction = @payload.fetch("instruction").to_s.first(2_000)
        action, arguments = Studio::Director::PwaIntent.resolve(instruction: instruction, scene: scene, object_id: @payload["object_id"])
        slug = "studio.scene_object.#{action}"
        arguments.merge!("scene_id" => scene.id, "user_id" => @access.user.id, "site_id" => @access.site_id)
        receipt = ::Nevaeh.handle(event_type: "#{slug}.requested", source: "lightek_pwa_director",
          actor: @access.user, payload: arguments, capability_hint: slug, instruction: instruction,
          args: [action, arguments], context: { "client" => "lightek_pwa", "scene_id" => scene.id }, correlation_id: SecureRandom.uuid)
        { work_item_id: receipt.work_item.id, capability: slug, status: receipt.work_item.status }
      end

      def operations_list
        project = @access.projects.find(@payload.fetch("project_id"))
        { publications: project.studio_publications.order(id: :desc).limit(30).map { |publication|
            { id: publication.id, status: publication.status, scheduled_at: publication.scheduled_at&.iso8601,
              error: publication.error_message, post_id: publication.metadata.to_h["post_id"] } },
          operations: project.studio_operations.order(id: :desc).limit(30).map do |operation|
          { id: operation.id, type: operation.operation_type, status: operation.status, error: operation.error_message,
            artifacts: operation.artifacts.select { |artifact| artifact.file.attached? }.map do |artifact|
              { id: artifact.id, kind: artifact.kind, filename: artifact.filename,
                url: Rails.application.routes.url_helpers.rails_blob_path(artifact.file, only_path: true) }
            end }
        end }
      end

      private

      def bounded_number(value, minimum, maximum)
        number = Float(value)
        raise ArgumentError, "Value is outside its supported range" unless number.finite? && number.between?(minimum, maximum)
        number
      end

      def color(value, length)
        values = Array(value)
        raise ArgumentError, "Invalid color" unless values.length == length
        values.map { |v| bounded_number(v, 0, 1) }
      end

      def copy_project(source, template:)
        @access.user.with_lock do
          key = @payload.fetch("request_key").to_s
          raise ArgumentError, "Request key required" if key.blank? || key.length > 100
          existing = @access.projects.find_by(request_key: key)
          return { project_id: existing.id, scene_id: existing.studio_scenes.order(:id).first&.id } if existing
          project = StudioProject.create!(owner: @access.user, site_id: @access.site_id, is_template: template,
            name: @payload.fetch("name", source.name), description: source.description, request_key: key)
          # The project callback creates a default scene; replace it with the
          # original hierarchy, without creating a second Scene 1.
          project.studio_scenes.destroy_all
          productions = source.productions.to_h do |production|
            copy = production.dup
            copy.studio_project = project
            copy.save!
            [production.id, copy]
          end
          source.studio_scenes.each do |scene|
            copy = scene.dup
            copy.studio_project = project
            copy.production = productions[scene.production_id]
            copy.save!
            copy.blender_source.attach(scene.blender_source.blob) if scene.blender_source.attached?
            copy.blender_bundle.attach(scene.blender_bundle.blob) if scene.blender_bundle.attached?
            object_ids={}
            scene.scene_objects.each do |object|
              child = object.dup
              child.studio_scene = copy
              child.save!
              object_ids[object.id]=child.id
            end
            settings=copy.settings.except("library_requests", "json_preset_requests")
            settings["active_camera_object_id"]=object_ids[scene.settings["active_camera_object_id"]] if scene.settings["active_camera_object_id"]
            copy.update!(settings:settings)
          end
          { project_id: project.id, scene_id: project.studio_scenes.order(:id).first&.id, is_template: template }
        end
      end
    end
  end
end
