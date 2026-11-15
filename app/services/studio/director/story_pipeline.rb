# frozen_string_literal: true
module Studio
  module Director
    class StoryPipeline
      STAGES=%w[characters simulation viewpoints script].freeze
      AGENTS={'characters'=>'sage','simulation'=>'warden','viewpoints'=>'nevaeh','script'=>'muse'}.freeze
      def self.start!(production:,actor:,values:,request_key:)
        Finishing.access(production,actor);key=Finishing.key!(request_key)
        data=values.deep_stringify_keys
        raise ArgumentError,'Use scene_id, characters, events, optional relationships and viewpoint_cameras' unless (data.keys-%w[scene_id characters events relationships viewpoint_cameras]).empty?
        scene=production.studio_scenes.find(data.fetch('scene_id'))
        cast=data.fetch('characters')
        raise ArgumentError,'Supply 1–16 fictional characters' unless cast.is_a?(Array) && cast.size.between?(1,16)
        cast=cast.map { |row| Personality.character(row) }
        ids=cast.map { |row| row['id'] }
        raise ArgumentError,'Character IDs must be unique' unless ids.uniq.size==ids.size
        events=data.fetch('events')
        raise ArgumentError,'Supply 1–32 authored story events' unless events.is_a?(Array) && events.size.between?(1,32)
        events=events.map do |event|
          raise ArgumentError,'Use text and visible_to for each story event' unless event.is_a?(Hash) && event.keys.sort==%w[text visible_to] && event['text'].is_a?(String) && event['text'].length.between?(1,400) && event['visible_to'].is_a?(Array) && (event['visible_to']-ids).empty?
          event.slice('text','visible_to')
        end
        relations=Relationships.normalize(scene,data.fetch('relationships',[]))
        cameras=data.fetch('viewpoint_cameras',{})
        raise ArgumentError,'Map character IDs to cameras placed in this scene' unless cameras.is_a?(Hash) && (cameras.keys-ids).empty? && cameras.values.all? { |id| scene.scene_objects.where(object_type:'camera').exists?(id:id) }
        operation=nil
        production.with_lock do
          operation=production.studio_operations.where(capability:'studio.direct.story').detect { |op| op.metadata['request_key']==key }
          if operation
            raise ArgumentError,'This simulation key belongs to different inputs' unless operation.metadata['input_fingerprint']==Finishing.digest(data)
            next
          end
          operation=scene.studio_operations.create!(studio_project:production.studio_project,production:production,operation_type:'story_simulation',provider:'nevaeh',capability:'studio.direct.story',status:'pending',intent:{'user_id'=>actor.id},manifest:{'characters'=>cast,'events'=>events,'relationships'=>relations,'viewpoint_cameras'=>cameras,'stages'=>{}},metadata:{'request_key'=>key,'input_fingerprint'=>Finishing.digest(data),'scene_signature'=>Finishing.scene_signature(scene),'deadline'=>2.hours.from_now.iso8601})
        end
        StudioStoryPipelineJob.perform_later(operation.id) unless operation.terminal?
        {'production_id'=>production.id,'story_operation_id'=>operation.id,'status'=>'dispatched','text'=>"Story workers queued. Use /produce story_status #{operation.id}. This is an authored narrative simulation, not a finished show."}
      end
      def self.find!(id,actor:)
        operation=StudioOperation.where(capability:'studio.direct.story').find(id)
        Producer.find!(operation.production_id,actor:actor)
        operation
      end
      def self.tick!(operation)
        actor=User.find(operation.intent.fetch('user_id'));find!(operation.id,actor:actor)
        operation.with_lock do
          return if operation.terminal?
          raise ArgumentError,'Story worker deadline reached; inspect its stage receipts' if Time.current>Time.iso8601(operation.metadata.fetch('deadline'))
          stages=operation.manifest.fetch('stages').deep_dup
          stage=STAGES.find { |name| stages.dig(name,'status')!='completed' }
          unless stage
            operation.update!(status:'completed',completed_at:Time.current)
            return
          end
          entry=stages[stage]
          if entry && entry['agent_run_id']
            run=NevaehAgentRun.find(entry['agent_run_id'])
            action=run.nevaeh_os_action
            raise ArgumentError,run.error.presence || action&.error.presence || 'Story worker failed' if run.status=='blocked' || action&.status=='failed'
            # The step updates its own stage receipt atomically with scene edits.
            return
          end
          result=NevaehOs::AgentWorkforce.create!(actor:actor,command:{'agent_ref'=>AGENTS.fetch(stage),'command'=>{'kind'=>'production','operation'=>'story_step','id'=>operation.production_id,'values'=>{'story_operation_id'=>operation.id,'stage'=>stage}}},key:"story-#{operation.id}-#{stage}")
          stages[stage]=result.merge('status'=>'queued')
          operation.update!(status:'running',started_at:operation.started_at || Time.current,manifest:operation.manifest.merge('stages'=>stages))
        end
      end
      def self.step!(production:,actor:,values:,request_key:)
        operation=find!(values.fetch('story_operation_id'),actor:actor)
        raise ArgumentError,'This story belongs to another production' unless operation.production_id==production.id
        stage=values.fetch('stage');raise ArgumentError,'Unknown story stage' unless STAGES.include?(stage)
        scene=operation.studio_scene
        scene.with_lock do
          operation.with_lock do
            raise ArgumentError,'Story simulation is no longer active' unless %w[pending running].include?(operation.status)
            data=operation.manifest.deep_dup;stages=data.fetch('stages')
            return {'story_operation_id'=>operation.id,'status'=>'completed','stage'=>stage} if stages.dig(stage,'status')=='completed'
            previous=STAGES.take(STAGES.index(stage))
            raise ArgumentError,'Finish prerequisite story workers first' unless previous.all? { |name| stages.dig(name,'status')=='completed' }
            raise ArgumentError,'The scene changed. Start a new story simulation to preserve those edits.' unless Finishing.scene_signature(scene)==operation.metadata.fetch('scene_signature')
            case stage
            when 'characters'
              data['character_briefs']=data.fetch('characters').map { |character| character.slice('id','name','goal','personality','knows','secret') }
            when 'simulation'
              data['simulation']=data.fetch('characters').map do |character|
                known=character.fetch('knows').dup
                beats=data.fetch('events').each_with_index.map do |event,index|
                  observed=event.fetch('visible_to').include?(character['id'])
                  known << event['text'] if observed
                  {'event_index'=>index,'observed'=>observed,'known_facts'=>known.uniq.dup,'reaction'=>observed ? "#{character['name']} #{character.dig('personality','habit')} while pursuing: #{character['goal']}" : "#{character['name']} continues with only their prior knowledge"}
                end
                {'character_id'=>character['id'],'beats'=>beats}
              end
            when 'viewpoints'
              Relationships.apply!(scene,data.fetch('relationships'));scene.reload
              shots=Array(scene.settings.dig('shot_board','shots')).map(&:deep_dup)
              camera_ids=data.fetch('viewpoint_cameras')
              data['viewpoints']=data.fetch('characters').map { |character| {'character_id'=>character['id'],'camera_id'=>camera_ids[character['id']],'perspective'=>'limited to this character’s known facts'} }
              shots.each_with_index do |shot,index|
                character=data.fetch('characters')[index % data.fetch('characters').size]
                shot['camera_id']=camera_ids[character['id']] if camera_ids[character['id']]
                shot['notes']="Viewpoint: #{character['name']}. Goal: #{character['goal']}. #{character.dig('personality','habit')}. Only use facts known to this character."
              end
              if shots.any?
                normalized=Studio::Shots::Board.normalize(scene,shots)
                board=scene.settings.fetch('shot_board').merge('shots'=>normalized,'revision'=>scene.settings.dig('shot_board','revision').to_i+1)
                scene.update!(settings:scene.settings.merge('shot_board'=>board))
              end
            when 'script'
              lines=data.fetch('characters').map do |character|
                state=data.fetch('simulation').find { |row| row['character_id']==character['id'] }
                # A bounded scaffold sourced only from this viewpoint; secrets are
                # kept in character briefs and are not silently given to others.
                known=state.fetch('beats').last.fetch('known_facts')
                "#{character['name'].upcase} (#{character.dig('personality','strength')}; #{character.dig('personality','habit')})\nI want #{character['goal']}. #{known.empty? ? 'I need to find out what happened.' : 'What I know: '+known.last}"
              end
              script="DRAFT · CHARACTER VIEWPOINTS\n\n"+lines.join("\n\n")
              workspace=scene.settings.fetch('workspace',{}).deep_dup;workspace['story']||={};workspace['story']['scriptDraft']=script
              scene.update!(settings:scene.settings.merge('workspace'=>workspace,'story_simulation'=>{'operation_id'=>operation.id,'viewpoints'=>data['viewpoints']}))
              data['script_draft']=script
            end
            stages[stage]=stages.fetch(stage,{}).merge('status'=>'completed','completed_at'=>Time.current.iso8601)
            operation.update!(manifest:data,metadata:operation.metadata.merge('scene_signature'=>Finishing.scene_signature(scene)))
          end
        end
        {'story_operation_id'=>operation.id,'stage'=>stage,'status'=>'completed','text'=>"#{stage} worker completed with saved evidence."}
      end
      def self.receipt(operation)
        {'story_operation_id'=>operation.id,'production_id'=>operation.production_id,'status'=>operation.status,'error'=>operation.error_message,'stages'=>operation.manifest['stages'],'simulation'=>operation.manifest['simulation'],'viewpoints'=>operation.manifest['viewpoints'],'script_draft'=>operation.manifest['script_draft'],'text'=>'Story pipeline '+operation.status+'. Draft character viewpoints and authored event simulation remain editable.'}.compact
      end
    end
  end
end
