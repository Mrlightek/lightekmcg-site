# frozen_string_literal: true
module Studio
  module Director
    class Rehearsal
      CAPABILITY='studio.direct.rehearsal'
      def self.production!(id,actor:)
        production=::Production.joins(:studio_project).where(studio_projects:{owner_id:actor.id}).find(id)
        Studio::Broadcasting::Access.authorize!(actor.reload,production.studio_project.site)
        production
      end
      def self.start!(production:,actor:,values:,request_key:)
        production!(production.id,actor:actor);Finishing.key!(request_key)
        data=values.deep_stringify_keys
        raise ArgumentError,'Use scene_id, goals and preview_seconds' unless (data.keys-%w[scene_id goals preview_seconds]).empty?
        scene=production.studio_scenes.find(data['scene_id'] || production.studio_scenes.order(:id).first!.id)
        seconds=Integer(data.fetch('preview_seconds',6))
        raise ArgumentError,'Choose a 1–12 second rehearsal preview' unless seconds.between?(1,12)
        goals=data.fetch('goals',{})
        raise ArgumentError,'Use up to sixteen character XY goals' unless goals.is_a?(Hash) && goals.size<=16
        goals.each do |id,point|
          object=scene.scene_objects.find(id)
          raise ArgumentError,'Select a placed Cast character' unless object.definition['character_profile'] || object.definition['director_speaker'] || object.definition['blocking_actor']
          raise ArgumentError,'A rehearsal goal needs two finite coordinates within sixteen metres' unless point.is_a?(Array) && point.size==2 && point.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs<=16 }
        end
        operation=nil
        scene.with_lock do
          operation=scene.studio_operations.where(capability:CAPABILITY).detect { |op| op.metadata['request_key']==request_key }
          if operation
            raise ArgumentError,'This rehearsal request belongs to different inputs' unless operation.metadata['input_fingerprint']==Finishing.digest(data)
            next
          end
          Finishing.validate_continuity!(production,scene)
          manifest=::Blender::ManifestBuilder.new(scene).call.deep_dup
          settings=manifest.fetch('scene').fetch('settings')
          fps=Float(settings.fetch('fps',24))/Float(settings.fetch('fps_base',1))
          raise ArgumentError,'Split this scene into at most 2400 frames for rehearsal' unless (Integer(settings.fetch('frame_end'))-Integer(settings.fetch('frame_start',1))+1).between?(1,2400)
          settings.merge!('resolution_x'=>384,'resolution_y'=>216,'resolution_percentage'=>100,'samples'=>8,'render_engine'=>'BLENDER_WORKBENCH','_director_rehearsal'=>{'goals'=>goals,'preview_frames'=>(seconds*fps).round})
          manifest['outputs']={'blend'=>true,'animation'=>true,'preview'=>false}
          operation=scene.studio_operations.create!(studio_project:production.studio_project,production:production,operation_type:'build_scene',provider:'blender',capability:CAPABILITY,status:'pending',intent:{'user_id'=>actor.id},manifest:manifest,metadata:{'request_key'=>request_key,'input_fingerprint'=>Finishing.digest(data),'scene_signature'=>Finishing.scene_signature(scene),'draft_preview'=>true,'director_rehearsal'=>true})
        end
        StudioRehearsalJob.perform_later(operation.id) if operation.status=='pending'
        receipt(operation,actor:actor)
      end
      def self.find!(id,actor:)
        operation=StudioOperation.where(capability:CAPABILITY).find(id)
        production!(operation.production_id,actor:actor)
        operation
      end
      def self.receipt(operation,actor:)
        find!(operation.id,actor:actor)
        links=operation.artifacts.where(kind:'video').filter_map do |artifact|
          next unless artifact.file.attached?
          {'label'=>'Watch rehearsal','url'=>Rails.application.routes.url_helpers.rails_blob_path(artifact.file,only_path:true)}
        end
        report=operation.metadata['rehearsal_report']
        stale=operation.status=='completed' && !operation.metadata['applied_at'] && Finishing.scene_signature(operation.studio_scene)!=operation.metadata['scene_signature']
        {'production_id'=>operation.production_id,'scene_id'=>operation.studio_scene_id,'rehearsal_id'=>operation.id,'status'=>stale ? 'stale' : operation.status=='completed' ? (report&.fetch('status') || 'needs_attention') : operation.status,'stale'=>stale,'report'=>report,'applied'=>operation.metadata['applied_at'],'error'=>operation.error_message,'links'=>links,'text'=>"Rehearsal #{operation.status}. Corrections stay in a preview until explicitly applied."}.compact
      end
      def self.apply!(operation:,actor:)
        find!(operation.id,actor:actor)
        scene=operation.studio_scene
        scene.with_lock do
          operation.with_lock do
            return receipt(operation,actor:actor) if operation.metadata['applied_at']
            raise ArgumentError,'Only a verified ready rehearsal can be applied' unless operation.status=='completed' && operation.metadata.dig('rehearsal_report','status')=='ready'
            raise ArgumentError,'The scene changed after this rehearsal. Rehearse the current version.' unless Finishing.scene_signature(scene)==operation.metadata['scene_signature']
            Studio::Gatekeeper::Client.authorize!(capability:'studio.workspace.scene.save',subject:scene,context:{project_id:scene.studio_project_id,rehearsal_id:operation.id})
            Array(operation.metadata.dig('rehearsal_report','corrections')).each do |row|
              object=scene.scene_objects.find(row.fetch('object_id'))
              frames=row.fetch('frames')
              raise ArgumentError,'The rehearsal has an invalid path' unless frames.is_a?(Array) && frames.size.between?(1,64) && frames.all? { |frame| frame['frame'].is_a?(Integer) && frame['frame'].between?(Integer(scene.settings.fetch('frame_start',1)),Integer(scene.settings.fetch('frame_end',2400))) && frame['location'].is_a?(Array) && frame['location'].size==3 && frame['location'].all? { |v| v.is_a?(Numeric) && v.finite? && v.abs<=1000 } }
              # Replace root translation only; authored rotation/scale keys still belong to the artist.
              animation=object.definition.fetch('animation',{}).deep_dup
              original=Array(animation['frames']).map { |frame| frame.except('location') }.select { |frame| (frame.keys-['frame']).any? }
              merged=(frames.map { |frame| frame.fetch('frame') }+original.map { |frame| frame.fetch('frame') }).uniq.sort.map do |number|
                left=frames.reverse.find { |frame| frame['frame']<=number } || frames.first
                right=frames.find { |frame| frame['frame']>=number } || frames.last
                fraction=right['frame']==left['frame'] ? 0 : (number-left['frame']).to_f/(right['frame']-left['frame'])
                location=left['location'].zip(right['location']).map { |a,b| a+(b-a)*fraction }
                (original.find { |frame| frame['frame']==number } || {'frame'=>number}).merge('location'=>location)
              end
              raise ArgumentError,'This path needs more than 100 animation keys; simplify the authored motion first' if merged.size>100
              object.update!(definition:object.definition.merge('location'=>frames.first.fetch('location'),'animation'=>animation.merge('fps'=>scene.settings.fetch('fps',24),'frames'=>merged)))
            end
            scene.update!(settings:scene.settings.merge('native_revision'=>scene.settings.fetch('native_revision',0).to_i+1))
            operation.update!(metadata:operation.metadata.merge('applied_at'=>Time.current.iso8601))
          end
        end
        receipt(operation,actor:actor)
      end
    end
  end
end
