# frozen_string_literal: true

module Studio
  module Workers
    module Activity
      LABELS = {
        "studio.workspace.ai.generate"=>"Generation",
        "studio.workspace.render.quote"=>"3D render",
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
        {id:item.id,task_uuid:item.correlation_id,label:LABELS.fetch(item.kind),status:status,asset_id:asset&.id,
          operation_id:operation&.id,teach:verified && Ability.new(access.user).can?(:manage,NevaehWorkflow)}
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
