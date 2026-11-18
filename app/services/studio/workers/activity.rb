# frozen_string_literal: true

module Studio
  module Workers
    module Activity
      LABELS = {
        "studio.workspace.workflow.create"=>"2D scene render",
        "studio.workspace.ai.generate"=>"Generation",
        "studio.workspace.render.quote"=>"3D render",
        "studio.workspace.blender.preview"=>"3D draft",
        "studio.workspace.performance.preview"=>"Character preview",
        "studio.workspace.timeline.quote"=>"Media export",
        "studio.workspace.asset.publish"=>"Publishing",
        "studio.workspace.artifact.publish"=>"Publishing"
      }.freeze

      module_function

      def for_scene(access, scene)
        scope(access.user, access.site_id)
          .where("CAST(args -> 1 ->> 'scene_id' AS TEXT) = ?",scene.id.to_s)
          .order(id: :desc).limit(40).filter_map do |item|
            next if item.kind=="studio.workspace.blender.preview" && !item.args.dig(1,"scene_preset")
            next if item.kind=="studio.workspace.performance.preview" && item.args.dig(1,"operation_id")
            next if item.kind=="studio.workspace.timeline.quote" && item.args.dig(1,"social_prepare") && !item.result.to_h["operation_id"] && item.done?
            row(item,access,scene)
          end.uniq { |entry| entry[:operation_id] ? [entry[:label],entry[:operation_id]] : entry[:id] }
      end

      def scope(actor,site_id)
        DymondDispatch::WorkItem.where(kind:LABELS.keys)
          .where("CAST(args -> 1 ->> 'user_id' AS TEXT) = ? AND CAST(args -> 1 ->> 'site_id' AS TEXT) = ?",actor.id.to_s,site_id.to_s)
      end

      def row(item,access,scene)
        data=item.result.to_h
        asset=StudioAsset.for_actor(access).find_by(id:data["asset_id"],site_id:access.site_id) if data["asset_id"]
        operation=scene.studio_operations.find_by(id:data["operation_id"]) if data["operation_id"]
        publication=scene.studio_project.studio_publications.find_by(id:data["publication_id"]) if data["publication_id"]
        checkpoint=operation && Studio::Compute::Queue.economy?(operation) && operation.status=="failed" &&
          operation.paid? && operation.manifest.dig("outputs","animation") && !operation.metadata["draft_preview"]
        status=if item.failed?
          "failed"
        elsif !item.done?
          item.status
        elsif checkpoint
          "recoverable"
        else
          asset&.status || operation&.status || publication_status(publication) || "processing"
        end
        verified=(status=="ready" && asset&.proxy&.attached?) ||
          (status=="completed" && operation&.artifacts&.any? { |artifact| artifact.file.attached? })
        status="failed" if status.in?(%w[ready completed]) && !verified
        working=if verified && asset && asset.metadata["ai_profile"]
          {"quality_profile"=>asset.metadata["ai_profile"],"genesis_worker_id"=>asset.metadata.dig("ai_intent","genesis_worker_id") || asset.metadata.dig("ai_worker","installation_id"),
            "seed"=>asset.metadata.dig("ai_intent","seed")}.compact
        end
        {id:item.id,task_uuid:item.correlation_id,label:LABELS.fetch(item.kind),status:status,asset_id:asset&.id,
          operation_id:operation&.id,recovery:status.in?(%w[failed recoverable]) ? Studio::Compute::Recovery.advice(asset:asset,operation:operation,work_error:item.error,checkpoint:checkpoint) : nil,
          working_parameters:working,
          teach:verified && (item.kind!="studio.workspace.blender.preview" || item.args.dig(1,"scene_preset").present?) && Ability.new(access.user).can?(:manage,NevaehWorkflow)}
      end

      def retry_economy_inputs!(actor, site, receipt_id)
        item=scope(actor,site.id).where(kind:"studio.workspace.ai.generate").find(receipt_id)
        access=Studio::PwaAccess.new("user_id"=>actor.id,"site_id"=>site.id)
        inputs=item.args.fetch(1)
        scene=access.scene!(inputs.fetch("scene_id"))
        raise ActiveRecord::RecordNotFound unless scene.studio_project.site_id==site.id
        evidence=row(item,access,scene)
        unless evidence.dig(:recovery,:action)=="retry_economy"
          raise ArgumentError,"This result doesn’t have an Economy retry. Check the worker before submitting again."
        end
        inputs.slice(*Studio::Compute::Guardrails::GENERATION_INPUTS).merge("quality_profile"=>"economy",
          "steps"=>inputs.fetch("steps",20).to_i.clamp(1,20),"request_key"=>"economy-retry-#{item.id}","user_id"=>actor.id,"site_id"=>site.id)
      end

      def publication_status(publication)
        return unless publication
        if publication.status=="published" && publication.metadata["youtube_submission"]
          upload=LightekPwa::YoutubeUpload.find_by(id:publication.metadata["youtube_upload_id"])
          return "delivered" if upload&.status=="ready"
          return "failed" if upload&.status.in?(%w[failed withdrawn reconciliation_required])
          return "publishing"
        end
        publication.status=="published" ? "delivered" : publication.status
      end
    end
  end
end
