# frozen_string_literal: true
module Studio
  module Workers
    class Workspace
      ACTIONS = %w[scene_save project_delete template_save template_use render_quote render_checkout operations_list artifact_publish director_execute visual_save asset_import assets_list timeline_save timeline_quote asset_place].freeze
      def self.perform(action, payload = {}) = new(action, payload).perform
      def initialize(action, payload)
        @action = action.to_s
        @payload = payload.to_h.deep_stringify_keys
        @access = Studio::PwaAccess.new(@payload)
      end
      def perform
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
        { assets: StudioAsset.for_actor(@access).order(id: :desc).limit(100).map { |asset|
          { id:asset.id,name:asset.name,kind:asset.kind,status:asset.status,error:asset.error_message,metadata:asset.metadata,
            url:"/api/lightek/pwa/assets/#{asset.id}/original",proxy_url:asset.proxy.attached? ? "/api/lightek/pwa/assets/#{asset.id}/proxy" : nil,
            thumbnail_url:asset.thumbnail.attached? ? "/api/lightek/pwa/assets/#{asset.id}/thumbnail" : nil } } }
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
            scene.scene_objects.each do |object|
              child = object.dup
              child.studio_scene = copy
              child.save!
            end
          end
          { project_id: project.id, scene_id: project.studio_scenes.order(:id).first&.id, is_template: template }
        end
      end
    end
  end
end
