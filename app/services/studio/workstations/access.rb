module Studio
  module Workstations
    class Access
      attr_reader :workspace
      def initialize(user:,site:)
        @workspace=Studio::PwaAccess.new("user_id"=>user.id,"site_id"=>site.id)
        LightekPwa::Policy.new(user:user,site:site).authorize!("studio")
      end
      def sessions
        scope=StudioWorkstation.where(site_id:workspace.site_id)
        workspace.user.role.to_s=="super_admin" ? scope : scope.where(owner_id:workspace.user.id)
      end
      def find!(key) = sessions.find_by!(session_key:key)
      def create!(payload,origin:)
        scene=workspace.scene!(payload.fetch("scene_id"));key=payload.fetch("request_key").to_s
        raise ArgumentError,"A workstation request key is required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
        workspace.user.with_lock do
          existing=StudioWorkstation.find_by(owner_id:workspace.user.id,request_key:key)
          if existing
            raise ArgumentError,"Request belongs to another scene or site" unless existing.site_id==workspace.site_id && existing.studio_scene_id==scene.id
            return existing
          end
          raise ArgumentError,"Close the current native workstation before opening another" if StudioWorkstation.where(owner_id:workspace.user.id,status:%w[starting building ready saving]).where("expires_at > ?",Time.current).exists?
          session=StudioWorkstation.create!(owner:workspace.user,site_id:workspace.site_id,studio_scene:scene,session_key:SecureRandom.hex(16),request_key:key,expires_at:4.hours.from_now,metadata:{"origin"=>origin,"scene_lock_version"=>scene.lock_version,"credits"=>Blender::ManifestBuilder.new(scene).call["credits"]})
          operation=scene.studio_operations.create!(studio_project:scene.studio_project,production:scene.production,operation_type:"build_scene",provider:"blender",capability:"studio.workspace.workstation.start",status:"pending",intent:{"user_id"=>workspace.user.id},manifest:Blender::ManifestBuilder.new(scene).call.merge("outputs"=>{"blend"=>true,"bundle"=>scene.blender_bundle.attached?}),metadata:{"workstation_source"=>true})
          session.update!(metadata:session.metadata.merge("operation_id"=>operation.id))
          StudioWorkstationStartJob.perform_later(session.id)
          session
        end
      end
    end
  end
end
