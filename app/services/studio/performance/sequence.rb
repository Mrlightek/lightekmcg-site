# frozen_string_literal: true
require "digest"
module Studio
  module Performance
    class Sequence
      CAPABILITY="studio.workspace.sequence.prepare"
      PREVIEW_SETTINGS=%w[resolution_x resolution_y samples frame_current].freeze
      def self.canonical(value)
        case value
        when Hash then value.keys.sort.to_h { |key| [key,canonical(value[key])] }
        when Array then value.map { |item| canonical(item) }
        else value
        end
      end
      def self.signature(scene_data)
        data=scene_data.deep_dup
        settings=data.fetch("settings")
        aspect=(Float(settings.fetch("resolution_x"))/Float(settings.fetch("resolution_y"))).round(2)
        data["settings"]=settings.except(*PREVIEW_SETTINGS).merge("sequence_aspect"=>aspect)
        Digest::SHA256.hexdigest(canonical(data).to_json)
      end
      def self.current_signature(scene) = signature(Blender::ManifestBuilder.new(scene).call.fetch("scene"))
      def self.source(access,id)
        parent=CharacterScene.find(access,id)
        raise ArgumentError,"Finish the character preparation before adding it to a sequence" unless parent.status=="completed"
        scene=access.scene!(parent.metadata.fetch("scene_id"))
        preview=scene.studio_operations.where(status:"completed",capability:"studio.workspace.performance.preview").find(parent.metadata.fetch("preview_id"))
        artifact=preview.artifacts.find_by!(kind:"video")
        raise ArgumentError,"The reviewed performance is unavailable" unless artifact.file.attached?
        stamp=current_signature(scene)
        raise ArgumentError,"This performance changed after its preview. Prepare and review a fresh performance." unless signature(preview.manifest.fetch("scene"))==stamp
        settings=preview.manifest.fetch("scene").fetch("settings")
        seconds=(settings.fetch("frame_end")-settings.fetch("frame_start",1)+1)/(Float(settings.fetch("fps"))/settings.fetch("fps_base",1))
        {parent:parent,scene:scene,preview:preview,artifact:artifact,signature:stamp,seconds:seconds}
      end
      def self.full_export(row)
        row.fetch(:scene).studio_operations.where(status:"completed",provider:"blender").order(id: :desc).find do |op|
          !op.metadata["draft_preview"] && !op.metadata["shot_id"] && op.manifest.dig("outputs","animation") &&
            op.manifest["scene"] && signature(op.manifest["scene"])==row[:signature] && op.artifacts.where(kind:"video").any? { |artifact| artifact.file.attached? }
        end
      end
      def self.catalog(access:,scene_id:)
        scene=access.scene!(scene_id)
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        rows=scene.studio_project.studio_operations.where(capability:CharacterScene::CAPABILITY,status:"completed").where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s).order(id: :desc).limit(100).map do |parent|
          begin
            row=source(access,parent.id)
            {operation_id:parent.id,name:row[:scene].name,scene_id:row[:scene].id,seconds:row[:seconds],available:true,full_export_ready:!!full_export(row)}
          rescue ArgumentError,ActiveRecord::RecordNotFound,KeyError => error
            {operation_id:parent.id,name:parent.manifest.dig("inputs","name") || "Character performance #{parent.id}",available:false,error:error.message}
          end
        end
        {performances:rows}
      end
      def self.start(access:,payload:)
        source_scene=access.scene!(payload.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless source_scene.studio_project.site_id==access.site_id
        key=payload.fetch("request_key").to_s;name=payload.fetch("name","Scene sequence").to_s.strip;shots=payload.fetch("shots")
        raise ArgumentError,"Use a sequence request key" unless key.match?(/\A[a-zA-Z0-9_-]{8,80}\z/)
        raise ArgumentError,"Name the sequence using 1–120 characters" unless name.length.between?(1,120) && !name.include?("\0")
        raise ArgumentError,"Choose two to twelve ordered performances" unless shots.is_a?(Array) && shots.size.between?(2,12) && shots.all? { |shot| shot.is_a?(Hash) }
        identities={}
        rows=shots.map do |shot|
          row=source(access,shot.fetch("operation_id"))
          raise ActiveRecord::RecordNotFound unless row[:parent].studio_project_id==source_scene.studio_project_id
          row[:scene].scene_objects.each do |object|
            next unless (profile=object.definition["character_profile"])
            role=object.name.strip.downcase
            identity=[object.definition.fetch("asset_id"),profile.fetch("source_blob_id"),canonical(profile)]
            raise ArgumentError,"#{object.name} uses different Cast identities across these performances. Reuse its saved Cast asset in each shot." if identities[role] && identities[role]!=identity
            identities[role]=identity
          end
          first=Float(shot.fetch("in",0));last=Float(shot.fetch("out",row[:seconds]))
          raise ArgumentError,"Trim each clip within its reviewed performance (at least one twelfth of a second)" unless first.finite? && last.finite? && first>=0 && last<=row[:seconds]+0.001 && last-first>=1.0/12
          raise ArgumentError,"Use sources smaller than 50 MB each" if row[:artifact].file.blob.byte_size>50.megabytes
          {"preparation_id"=>row[:parent].id,"scene_id"=>row[:scene].id,"artifact_id"=>row[:artifact].id,"blob_id"=>row[:artifact].file.blob.id,"signature"=>row[:signature],"in"=>first,"out"=>last,"seconds"=>last-first,"name"=>row[:scene].name}
        end
        raise ArgumentError,"Keep total sequence source files within 100 MB" if rows.uniq { |row| row["blob_id"] }.sum { |row| ActiveStorage::Blob.find(row["blob_id"]).byte_size }>100.megabytes
        raise ArgumentError,"Keep the review cut within thirty seconds" if rows.sum { |row| row["seconds"] }>30
        inputs={"name"=>name,"shots"=>rows.map { |row| {"operation_id"=>row["preparation_id"],"in"=>row["in"],"out"=>row["out"]} }}
        operation=access.user.with_lock do
          scope=source_scene.studio_project.studio_operations.where(capability:CAPABILITY).where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s)
          previous=scope.where("metadata ->> 'request_key' = ?",key).first
          if previous
            raise ArgumentError,"This sequence key belongs to another cut" unless previous.studio_scene_id==source_scene.id && previous.manifest["inputs"]==inputs && previous.manifest["sources"]==rows
            next previous
          end
          raise ArgumentError,"Wait for your current sequence preview" if scope.where(status:%w[pending running]).exists? || scope.where("created_at > ?",1.minute.ago).count>=3
          op=source_scene.studio_operations.create!(studio_project:source_scene.studio_project,production:source_scene.production,operation_type:"sequence_preview",provider:"ffmpeg",capability:CAPABILITY,status:"pending",intent:{"user_id"=>access.user.id},manifest:{"inputs"=>inputs,"sources"=>rows},metadata:{"request_key"=>key,"draft_preview"=>true,"deadline"=>10.minutes.from_now.iso8601})
          rows.map { |row| row["blob_id"] }.uniq.each { |id| op.performance_sources.attach(ActiveStorage::Blob.find(id)) };op
        end
        StudioSequencePreviewJob.perform_later(operation.id) if operation.status=="pending"
        receipt(access:access,id:operation.id)
      end
      def self.find(access,id)
        op=StudioOperation.where(capability:CAPABILITY,studio_project_id:access.projects.where(site_id:access.site_id).select(:id)).find(id)
        raise ActiveRecord::RecordNotFound unless op.intent["user_id"]==access.user.id
        op
      end
      def self.check!(operation, sources:true)
        access=Studio::PwaAccess.new("user_id"=>operation.intent.fetch("user_id"),"site_id"=>operation.studio_project.site_id)
        find(access,operation.id)
        LightekPwa::Policy.new(user:access.user,site:operation.studio_project.site).authorize!("studio")
        LightekPwa::Network.require_studio_write!(user:access.user,site:operation.studio_project.site,capability:CAPABILITY) if defined?(LightekPwa::Network)
        return access unless sources
        operation.manifest.fetch("sources").each do |saved|
          row=source(access,saved.fetch("preparation_id"))
          raise ArgumentError,"A source performance changed. Prepare a new sequence cut." unless row[:signature]==saved["signature"] && row[:artifact].id==saved["artifact_id"] && row[:artifact].file.blob.id==saved["blob_id"] && row[:parent].studio_project_id==operation.studio_project_id
        end
        access
      end
      def self.receipt(access:,id:)
        op=find(access,id);artifact=op.status=="completed" && op.artifacts.order(id: :desc).find_by(kind:"video")
        {operation_id:op.id,status:op.status,error:op.error_message,inputs:op.manifest["inputs"],seconds:op.manifest.fetch("sources").sum { |row| row["seconds"] },edit_scene_id:op.metadata["edit_scene_id"],url:artifact && artifact.file.attached? ? Rails.application.routes.url_helpers.rails_blob_path(artifact.file,only_path:true) : nil}.compact
      end
      def self.latest(access:,scene_id:)
        scene=access.scene!(scene_id);raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==access.site_id
        op=scene.studio_operations.where(capability:CAPABILITY).where("CAST(intent ->> 'user_id' AS TEXT) = ?",access.user.id.to_s).order(id: :desc).first
        op ? receipt(access:access,id:op.id) : {status:"idle"}
      end
      def self.retry(access:,id:)
        op=find(access,id);check!(op)
        op.with_lock do
          raise ArgumentError,"Only failed sequence previews can retry" unless op.status=="failed"
          op.update!(status:"pending",completed_at:nil,error_message:nil,metadata:op.metadata.merge("deadline"=>10.minutes.from_now.iso8601))
        end
        StudioSequencePreviewJob.perform_later(op.id);receipt(access:access,id:id)
      end
      def self.quote(access:,payload:)
        op=find(access,payload.fetch("operation_id"));check!(op,sources:!op.metadata["export_id"])
        raise ArgumentError,"Finish and review the sequence preview first" unless op.status=="completed" && payload["reviewed"]==true
        existing=op.with_lock do
          if op.metadata["export_id"]
            scene=op.studio_project.studio_scenes.find(op.metadata.fetch("edit_scene_id"))
            raise ArgumentError,"The sequence edit changed. Export its current version from Timeline & Edit." unless scene.settings["timeline"]==op.metadata["full_timeline"]
            export=scene.studio_operations.find(op.metadata["export_id"])
            if export.status=="failed" && export.paid?
              export.with_lock do
                if export.status=="failed"
                  export.update!(status:"pending",error_message:nil,completed_at:nil)
                  ExecuteStudioOperationJob.perform_later(export.id)
                end
              end
            end
            {operation_id:export.id,status:export.status,quote:export.cost_quote,edit_scene_id:scene.id}
          end
        end
        return existing if existing
        rows=op.manifest.fetch("sources").map { |saved| [saved,source(access,saved["preparation_id"])] }
        exports=rows.map { |_,row| full_export(row) }
        missing=rows.each_with_index.filter_map { |(saved,row),index| {operation_id:row[:parent].id,scene_id:row[:scene].id,name:saved["name"]} unless exports[index] }.uniq { |row| row[:operation_id] }
        return {status:"source_exports_required",missing:missing} if missing.any?
        assets=exports.map do |export|
          artifact=export.artifacts.where(kind:"video").find { |item| item.file.attached? }
          result=Studio::Workers::Workspace.perform("artifact_reuse",{"user_id"=>access.user.id,"site_id"=>access.site_id,"project_id"=>op.studio_project_id,"artifact_id"=>artifact.id})
          StudioAsset.for_actor(access).where(site_id:access.site_id).find(result[:asset_id])
        end
        raise ArgumentError,"A source export failed to import. Retry it in Media Library." if assets.any? { |asset| asset.status=="failed" }
        return {status:"processing_sources",asset_ids:assets.map(&:id)} unless assets.all? { |asset| asset.status=="ready" }
        op.with_lock do
          check!(op)
          offset=0
          clips=op.manifest["sources"].each_with_index.map do |saved,index|
            row={"asset_id"=>assets[index].id,"in"=>saved["in"],"out"=>saved["out"],"start"=>offset};offset+=saved["seconds"];row
          end
          assets.each_with_index do |asset,index|
            artifact=exports[index].artifacts.where(kind:"video").find { |item| item.file.attached? }
            raise ArgumentError,"A full source import changed. Restore that export before preparing this sequence." unless asset.file.attached? && asset.file.blob.id==artifact.file.blob.id
          end
          timeline=Studio::Editing::Timeline.normalize({"width"=>1280,"height"=>720,"fps"=>24,"clips"=>clips},assets:assets.index_by(&:id))
          scene=op.studio_project.studio_scenes.find_by(id:op.metadata["edit_scene_id"])
          unless scene
            scene=op.studio_project.studio_scenes.create!(production:op.production,name:op.manifest.dig("inputs","name"),settings:StudioScene.default_settings.merge("timeline"=>timeline))
            op.update!(metadata:op.metadata.merge("edit_scene_id"=>scene.id,"full_timeline"=>timeline))
          end
          scene.with_lock do
            raise ArgumentError,"The sequence edit changed. Export its current version from Timeline & Edit." unless scene.settings["timeline"]==op.metadata["full_timeline"] && timeline==op.metadata["full_timeline"]
            previous=scene.studio_operations.find_by(id:op.metadata["export_id"])
            return {operation_id:previous.id,status:previous.status,quote:previous.cost_quote,edit_scene_id:scene.id} if previous
            result=Studio::Workers::Workspace.perform("timeline_quote",{"user_id"=>access.user.id,"site_id"=>access.site_id,"scene_id"=>scene.id})
            export=scene.studio_operations.find(result[:operation_id])
            blobs=assets.to_h { |asset| [asset.id.to_s,asset.file.blob.id] }
            export.update!(manifest:export.manifest.merge("sequence_source_blobs"=>blobs))
            assets.map { |asset| asset.file.blob }.uniq.each { |blob| export.performance_sources.attach(blob) }
            op.update!(metadata:op.metadata.merge("export_id"=>result[:operation_id]));result.merge(edit_scene_id:scene.id)
          end
        end
      end
    end
  end
end
