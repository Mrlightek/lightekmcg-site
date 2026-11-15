# frozen_string_literal: true
require 'digest'
module Studio
  module Director
    # Reuse Cast, Take, MotionPlan and Studio's publication records. No synthetic
    # completion: the master must contain a current, full-length scene export.
    class Finishing
      NATIVE_DESTINATIONS = %w[lightek_social lightek_streaming octavia].freeze
      def self.key!(key)
        raise ArgumentError, 'Use a request key of 16–100 letters, digits, underscores or hyphens' unless key.to_s.match?(/\A[a-zA-Z0-9_-]{16,100}\z/)
        key.to_s
      end
      def self.digest(value) = Digest::SHA256.hexdigest(value.to_json)
      def self.access(production, actor)
        Producer.find!(production.id, actor: actor)
        Studio::PwaAccess.new('user_id'=>actor.id, 'site_id'=>production.studio_project.site_id)
      end
      def self.animate!(production:, actor:, values:, request_key:)
        key = key!(request_key)
        workspace = access(production, actor)
        data = values.deep_stringify_keys
        raise ArgumentError, 'Use scene_id, cast_asset_id, voice_operation_id, cue_index, lock_version and optional motion_clips' unless (data.keys-%w[scene_id cast_asset_id voice_operation_id cue_index lock_version motion_clips facing_axis listener_object_id]).empty?
        scene = production.studio_scenes.find(data.fetch('scene_id'))
        result = nil
        actor.with_lock do
        production.with_lock do
        scene.with_lock do
          receipts = scene.settings.fetch('director_performances',{})
          if receipts[key]
            raise ArgumentError, 'This performance key belongs to different direction' unless receipts[key]['fingerprint']==digest(data)
            return receipts[key]
          end
          raise ArgumentError, 'The scene changed. Refresh before directing the character.' unless scene.lock_version==Integer(data.fetch('lock_version'))
          voice = scene.studio_operations.where(capability:'studio.direct.voice',status:'completed').find(data.fetch('voice_operation_id'))
          index = Integer(data.fetch('cue_index'))
          raise ArgumentError, 'Choose a dialogue cue from this scene' unless index>=0 && index<Array(voice.manifest['dialogue']).size
          cue = voice.manifest.fetch('dialogue').fetch(index)
          audio = StudioAsset.for_actor(workspace).where(site_id:workspace.site_id,status:'ready',kind:'audio').find(voice.manifest.fetch('asset_ids').fetch(index))
          cast = StudioAsset.for_actor(workspace).where(site_id:workspace.site_id,status:'ready',kind:'blend').find(data.fetch('cast_asset_id'))
          profile = cast.metadata.fetch('character_profile') { raise ArgumentError, 'Register and bind this character in Cast first' }
          raise ArgumentError,'The registered character source changed; register its new version explicitly' unless cast.native.attached? && cast.native.blob.id==profile['source_blob_id']
          identities=production.metadata.fetch('director_cast',{}).deep_dup
          identity={'asset_id'=>cast.id,'source_blob_id'=>profile['source_blob_id'],'profile_sha256'=>digest(profile)}
          if identities[cue['speaker']] && identities[cue['speaker']]!=identity
            raise ArgumentError,'This speaker already has a different saved identity. Reuse the same registered Cast asset across scenes.'
          end
          series=production.metadata.dig('director','inputs','series_key')
          if series
            ::Production.joins(:studio_project).where(studio_projects:{owner_id:actor.id,site_id:production.studio_project.site_id}).where.not(id:production.id).find_each do |episode|
              next unless episode.metadata.dig('director','inputs','series_key')==series
              saved=episode.metadata.dig('director_cast',cue['speaker'])
              raise ArgumentError,'This speaker has a different identity in an earlier episode of this series. Reuse the saved Cast asset.' if saved && saved!=identity
            end
          end
          identities[cue['speaker']]=identity
          duration = audio.metadata.fetch('duration').to_f
          fps = scene.settings.fetch('fps',24).to_f/scene.settings.fetch('fps_base',1)
          raise ArgumentError, 'The dialogue must fit this scene' unless cue.fetch('start')+duration<=scene.settings.fetch('frame_end',1)/fps+0.05
          object = scene.scene_objects.find { |item| item.definition['director_speaker']==cue['speaker'] }
          raise ArgumentError, 'This character already has a take. Use another scene or edit its Performance workspace.' if object&.definition&.dig('performance')
          placed = Studio::Performance::Cast.place(access:workspace,payload:{'scene_id'=>scene.id,'asset_id'=>cast.id,'lock_version'=>scene.lock_version,'request_key'=>"director-#{digest(key)}-cast"})
          scene.reload
          object = scene.scene_objects.find(placed.fetch('object_id'))
          others=scene.scene_objects.select { |item| item.id!=object.id && item.definition['director_speaker'] }
          facing=data.fetch('facing_axis','-Y')
          raise ArgumentError,'Choose the character forward axis X, Y, -X or -Y' unless %w[X Y -X -Y].include?(facing)
          location=[others.size.even? ? -1.0 : 1.0,(others.size/2)*2.0,0.0]
          object.update!(definition:object.definition.merge('director_speaker'=>cue['speaker'],'director_facing_axis'=>facing,'location'=>location))
          if data['listener_object_id'] || others.size==1
            listener=data['listener_object_id'] ? scene.scene_objects.find(data['listener_object_id']) : others.first
            rows=[{'object_id'=>object.id,'look_at'=>listener.id,'facing_axis'=>facing,'personal_space'=>0.9}]
            if others.size==1 && !listener.definition['story_relation']
              rows << {'object_id'=>listener.id,'look_at'=>object.id,'facing_axis'=>listener.definition.fetch('director_facing_axis','-Y')}
            end
            Relationships.apply!(scene,rows);scene.reload
          elsif others.size>1
            raise ArgumentError,'Choose an explicit listener_object_id for a scene with more than two speakers'
          end
          production.update!(metadata:production.metadata.merge('director_cast'=>identities))
          expressions = profile.fetch('bindings',{}).key?('brow_raise') ? [{'control'=>'brow_raise','start'=>0,'end'=>[duration,0.6].min,'value'=>0.25}] : []
          gestures = profile.fetch('bones',{}).key?('head') ? [{'kind'=>'nod','start'=>0,'end'=>[duration,1.0].min,'strength'=>0.2}] : []
          take = Studio::Performance::Take.save(access:workspace,payload:{'scene_id'=>scene.id,'object_id'=>object.id,'audio_asset_id'=>audio.id,'source_out'=>duration,'start'=>cue['start'],'lock_version'=>scene.lock_version,'request_key'=>"director-#{digest(key)}-take",'expressions'=>expressions,'gestures'=>gestures})
          scene.reload
          if data['motion_clips']
            Studio::Performance::MotionPlan.save(access:workspace,payload:{'scene_id'=>scene.id,'object_id'=>object.id,'clips'=>data['motion_clips'],'lock_version'=>scene.lock_version,'motion_revision'=>0,'request_key'=>"director-#{digest(key)}-motion"})
            scene.reload
          end
          result = {'production_id'=>production.id,'fingerprint'=>digest(data),'scene_id'=>scene.id,'object_id'=>object.id,'audio_asset_id'=>audio.id,'duration'=>duration,'status'=>'prepared','lip_sync'=>'audio_envelope','text'=>'Editable mouth animation, available facial/gesture controls, and requested body motions saved. Render and review the character performance in Studio.'}
          scene.update!(settings:scene.settings.merge('director_performances'=>receipts.merge(key=>result),'spatial_direction'=>scene.settings.fetch('spatial_direction',{'units'=>'meters','personal_space'=>0.9,'collision_detection'=>true})))
        end
        end
        end
        result.merge('production_id'=>production.id)
      end
      def self.blocking!(production:,actor:,values:,request_key:)
        access(production,actor);key!(request_key)
        data=values.deep_stringify_keys
        raise ArgumentError,'Use scene_id, lock_version, relationships, personal_space and collision_detection' unless (data.keys-%w[scene_id lock_version relationships personal_space collision_detection]).empty?
        scene=production.studio_scenes.find(data.fetch('scene_id'))
        scene.with_lock do
          saved=scene.settings.fetch('blocking_receipts',{})
          if saved[request_key]
            raise ArgumentError,'This blocking key belongs to different direction' unless saved[request_key]['fingerprint']==digest(data)
            return saved[request_key]
          end
          raise ArgumentError,'Refresh before changing scene blocking' unless scene.lock_version==Integer(data.fetch('lock_version'))
          space=Float(data.fetch('personal_space',0.9));collision=data.fetch('collision_detection',true)
          raise ArgumentError,'Choose 0–5 metres of personal space and a collision boolean' unless space.finite? && space.between?(0,5) && [true,false].include?(collision)
          Relationships.apply!(scene,data.fetch('relationships',[]));scene.reload
          result={'production_id'=>production.id,'scene_id'=>scene.id,'fingerprint'=>digest(data),'status'=>'prepared','text'=>'Relative blocking, gaze, personal space, collision checks and camera focus saved. Frame-sampled spatial checks run in the Blender renderer.'}
          scene.update!(settings:scene.settings.merge('spatial_direction'=>{'units'=>'meters','personal_space'=>space,'collision_detection'=>collision},'blocking_receipts'=>saved.to_a.last(99).to_h.merge(request_key=>result)))
          result
        end
      end
      def self.validate_continuity!(production,scene)
        identities=production.metadata.fetch('director_cast',{})
        cast=scene.scene_objects.select { |object| object.definition['director_speaker'] }
        raise ArgumentError,'A speaker appears more than once in this scene' unless cast.map { |object| object.definition['director_speaker'] }.uniq.size==cast.size
        cast.each do |object|
          expected=identities[object.definition['director_speaker']]
          definition=object.definition;profile=definition['character_profile']
          raise ArgumentError,'A character identity changed. Restore the saved Cast source before rendering.' unless expected && profile && expected=={'asset_id'=>definition['asset_id'],'source_blob_id'=>profile['source_blob_id'],'profile_sha256'=>digest(profile)}
          source=StudioAsset.find(expected['asset_id'])
          raise ArgumentError,'The pinned Cast source is unavailable or changed' unless source.native.attached? && source.native.blob.id==expected['source_blob_id']
          raise ArgumentError,'Choose an explicit listener for each speaking character in this scene' if cast.size>1 && !definition.dig('story_relation','look_at')
        end
        Relationships.normalize(scene,scene.scene_objects.filter_map do |object|
          relation=object.definition['story_relation'];relation && relation.merge('object_id'=>object.id)
        end)
      end
      def self.scene_signature(scene)
        digest({'settings'=>scene.settings,'objects'=>scene.scene_objects.order(:id).map { |object| object.attributes.slice('id','object_type','definition') },'source_blob_id'=>scene.blender_source.attached? ? scene.blender_source.blob.id : nil})
      end
      def self.source!(production, scene, id, actor)
        validate_continuity!(production,scene)
        operation = production.studio_project.studio_operations.where(studio_scene_id:scene.id,status:'completed').joins(:artifacts).where(artifacts:{id:id}).first!
        artifact = operation.artifacts.find(id)
        raise ArgumentError, 'Use full scene video exports, not draft previews or individual shots' unless artifact.kind=='video' && artifact.file.attached? && artifact.file.blob.content_type.start_with?('video/') && !operation.metadata['draft_preview'] && !operation.metadata['shot_id']
        current = case operation.provider
        when 'ffmpeg' then operation.manifest['timeline']==scene.settings['timeline']
        when 'moviemasher'
          document = Studio::Editors::Document.new(scene:scene,actor:actor,kind:'video')
          operation.manifest['document']==document.normalize(document.load || {})
        when 'blender' then operation.manifest['scene']==::Blender::ManifestBuilder.new(scene).call['scene']
        else false
        end
        raise ArgumentError, 'Export the current scene revision before assembling the episode' unless current
        artifact
      end
      def self.render!(production:, actor:, request_key:)
        access(production,actor)
        key=key!(request_key)
        operations=[]
        production.with_lock do
          scenes=production.metadata.fetch('director').fetch('scene_ids').map { |id| production.studio_scenes.find(id) }
          scenes.each do |scene|
            scene.with_lock do
              validate_continuity!(production,scene)
              first=Integer(scene.settings.fetch('frame_start',1));last=Integer(scene.settings.fetch('frame_end'))
              raise ArgumentError, 'Full-scene rendering supports 1–2400 frames per scene. Split longer scenes in Studio first.' unless first>=1 && (last-first+1).between?(1,2400)
              signature=scene_signature(scene)
              operation=scene.studio_operations.where(capability:'studio.render.preview').detect { |op| op.metadata['director_render_key']==key }
              if operation
                raise ArgumentError, 'The scene changed. Request a new render of the current version.' unless operation.metadata['director_signature']==signature
              else
                manifest=::Blender::ManifestBuilder.new(scene).call
                manifest['outputs']={'blend'=>true,'animation'=>true,'bundle'=>scene.blender_bundle.attached?}
                operation=scene.studio_operations.create!(studio_project:production.studio_project,production:production,operation_type:'build_scene',provider:'blender',capability:'studio.render.preview',status:'awaiting_payment',intent:{'user_id'=>actor.id},manifest:manifest,metadata:{'director_render_key'=>key,'director_signature'=>signature})
                Studio::Billing::Quote.call(operation:operation,rail: :stripe_card)
              end
              operations << operation
            end
          end
        end
        {'production_id'=>production.id,'status'=>'awaiting_payment','render_operations'=>operations.map { |op| {'id'=>op.id,'scene_id'=>op.studio_scene_id,'status'=>op.status,'quote'=>op.cost_quote} },'text'=>'Full-scene render quotes are ready in Studio Delivery. Complete the existing render checkout; paid renders run through the existing worker. Then use /produce assemble PRODUCTION_ID to join the completed current scene exports.'}
      end
      def self.current_exports(production,actor)
        production.metadata.fetch('director').fetch('scene_ids').map do |id|
          scene=production.studio_scenes.find(id)
          artifact=scene.studio_operations.where(status:'completed').order(id: :desc).flat_map { |op| op.artifacts.where(kind:'video').order(id: :desc) }.find do |candidate|
            begin
              source!(production,scene,candidate.id,actor)
              true
            rescue ArgumentError, ActiveRecord::RecordNotFound
              false
            end
          end
          raise ArgumentError, "Finish a current full-scene video export for #{scene.name} before assembling" unless artifact
          artifact.id
        end
      end
      def self.assemble!(production:, actor:, values:, request_key:)
        access(production, actor)
        key = key!(request_key)
        data = values.deep_stringify_keys
        raise ArgumentError, 'Provide scene_artifact_ids in episode scene order, or leave inputs empty to select current exports' unless data.empty? || (data.keys==['scene_artifact_ids'] && data['scene_artifact_ids'].is_a?(Array))
        operation = nil
        production.with_lock do
          existing = production.studio_operations.where(capability:'studio.direct.assemble').detect { |op| op.metadata['request_key']==key }
          if existing
            raise ArgumentError, 'This assembly key belongs to different scene exports' unless existing.metadata['input_fingerprint']==digest(data)
            operation = existing
            next
          end
          scenes = production.metadata.fetch('director').fetch('scene_ids').map { |id| production.studio_scenes.find(id) }
          ids = data.fetch('scene_artifact_ids') { current_exports(production,actor) }
          raise ArgumentError, 'Select one full export per scene in episode order (at most 100 scenes)' unless scenes.size.between?(1,100) && ids.size==scenes.size && ids.uniq.size==ids.size
          sources = scenes.zip(ids).map do |scene,id|
            artifact = source!(production,scene,id,actor)
            fps = Float(scene.settings.fetch('fps',24))/Float(scene.settings.fetch('fps_base',1))
            seconds = (Integer(scene.settings.fetch('frame_end'))-Integer(scene.settings.fetch('frame_start',1))+1)/fps
            raise ArgumentError, 'A scene export must last 0.1–600 seconds' unless seconds.finite? && seconds.between?(0.1,600)
            {'scene_id'=>scene.id,'artifact_id'=>artifact.id,'blob_id'=>artifact.file.blob.id,'seconds'=>seconds,'signature'=>scene_signature(scene)}
          end
          raise ArgumentError, 'Use up to four hours and 10 GB of scene exports per master' unless sources.sum { |row| row['seconds'] }<=14400 && sources.sum { |row| ActiveStorage::Blob.find(row['blob_id']).byte_size }<=10.gigabytes
          credits = ids.flat_map { |id| Array(Artifact.find(id).studio_operation.manifest['credits']) }.uniq
          operation = production.studio_operations.create!(studio_project:production.studio_project,operation_type:'assemble_episode',provider:'ffmpeg',capability:'studio.direct.assemble',status:'pending',intent:{'user_id'=>actor.id},manifest:{'sources'=>sources,'credits'=>credits},metadata:{'request_key'=>key,'input_fingerprint'=>digest(data)})
          sources.each { |source| operation.performance_sources.attach(ActiveStorage::Blob.find(source['blob_id'])) }
        end
        StudioEpisodeAssemblyJob.perform_later(operation.id) if operation.status=='pending'
        {'production_id'=>production.id,'operation_id'=>operation.id,'status'=>operation.status,'text'=>"Episode assembly #{operation.status}. Use /produce status #{production.id}."}
      end
      def self.verify_sources!(operation)
        operation.manifest.fetch('sources').each do |row|
          scene = operation.production.studio_scenes.find(row.fetch('scene_id'))
          raise ArgumentError, 'The episode changed after assembly was requested. Export and assemble its current scenes.' unless scene_signature(scene)==row.fetch('signature')
          artifact = operation.studio_project.studio_operations.where(status:'completed').joins(:artifacts).where(artifacts:{id:row.fetch('artifact_id')}).first!.artifacts.find(row['artifact_id'])
          raise ArgumentError, 'A source export changed' unless artifact.file.attached? && artifact.file.blob.id==row.fetch('blob_id')
        end
      end
      def self.publish!(production:, actor:, values:, request_key:)
        access(production, actor)
        data = values.deep_stringify_keys
        raise ArgumentError, 'Review the master, then supply reviewed:true, artifact_id, destinations and optional title/content/audience' unless data['reviewed']==true && (data.keys-%w[reviewed artifact_id destinations title content audience connections tiktok_settings]).empty?
        destinations = data.fetch('destinations')
        raise ArgumentError, 'Choose community, OTT, TikTok or Instagram destinations.' unless destinations.is_a?(Array) && destinations.any? && (destinations-(NATIVE_DESTINATIONS+%w[tiktok instagram])).empty?
        raise ArgumentError, 'Use a title up to 160 characters and content up to 4000 characters' unless data.fetch('title',production.name).is_a?(String) && data.fetch('title',production.name).length.between?(1,160) && data.fetch('content','').is_a?(String) && data.fetch('content','').length<=4000
        connections=data.fetch('connections',{})
        destinations.grep(/\A(?:tiktok|instagram)\z/).each do |destination|
          connection=Studio::Publishers::SocialTransport.connection!(connections.fetch(destination),actor:actor,project:production.studio_project)
          raise ArgumentError,'Choose a matching connected social account' unless connection.provider==destination
        end
        key = key!(request_key)
        publications = []
        production.with_lock do
          operation = production.studio_operations.where(capability:'studio.direct.assemble',status:'completed').joins(:artifacts).where(artifacts:{id:data.fetch('artifact_id')}).first!
          verify_sources!(operation)
          artifact = operation.artifacts.find(data['artifact_id'])
          raise ArgumentError, 'The episode master is unavailable' unless artifact.file.attached? && artifact.kind=='video'
          destinations.uniq.each do |destination|
            pubkey = "#{key}-#{destination}"
            publication = production.studio_project.studio_publications.find_by(request_key:pubkey)
            publication ||= production.studio_publications.where(platform:destination,artifact_id:artifact.id).detect { |pub| pub.metadata['director_fingerprint']==digest(data) } if %w[tiktok instagram].include?(destination)
            if publication
              raise ArgumentError, 'This publication key belongs to different delivery inputs' unless publication.metadata['director_fingerprint']==digest(data)
            else
              publication = production.studio_project.studio_publications.create!(production:production,artifact:artifact,platform:destination,status:'draft',request_key:pubkey,
                metadata:{'user_id'=>actor.id,'site_id'=>production.studio_project.site_id,'title'=>data.fetch('title',production.name),'content'=>data.fetch('content',''),'audience'=>data.fetch('audience','everyone'),'sources'=>operation.manifest.fetch('credits',[]),'director_fingerprint'=>digest(data),'director_reviewed_at'=>Time.current.iso8601,'director_assembly_id'=>operation.id,'reviewed'=>true,'connection_id'=>connections[destination],'tiktok_settings'=>data['tiktok_settings']})
            end
            publications << publication
          end
        end
        publications.each { |publication| StudioPublicationDispatchJob.perform_later(publication.id) if %w[draft failed].include?(publication.status) }
        {'production_id'=>production.id,'status'=>'dispatched','publication_ids'=>publications.map(&:id),'text'=>"#{publications.size} reviewed deliveries submitted. Publication status follows actual publisher receipts."}
      rescue KeyError
        raise ArgumentError,'Choose a connected account for each social destination'
      end
    end
  end
end
