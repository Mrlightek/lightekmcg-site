# frozen_string_literal: true
require 'uri'
require 'digest'
module NevaehOs
  class Stage
    def initialize(actor) = @actor=actor
    def workspace = NevaehWorkspace.find_or_create_by!(user:@actor)
    def production!(id)
      production=::Production.joins(:studio_project).where(studio_projects:{owner_id:@actor.id}).find(id)
      Studio::Broadcasting::Access.authorize!(@actor.reload,production.studio_project.site)
      production
    end
    def page!(value)
      uri=URI.parse(value.to_s)
      raise ArgumentError,'Choose an internal dashboard page' unless uri.scheme.nil? && uri.host.nil? && uri.fragment.nil? && uri.path.match?(/\A\/dashboard\/[a-zA-Z0-9_\/-]+\z/) && !uri.path.start_with?('/dashboard/nevaeh') && !uri.path.match?(/(?:sign_out|logout|callback|\/files\/)/)
      allowed=URI.decode_www_form(uri.query.to_s).select { |key,value| %w[site_id scene_id project_id].include?(key) && value.match?(/\A[1-9][0-9]*\z/) }
      uri.path+(allowed.any? ? '?'+URI.encode_www_form(allowed) : '')
    rescue URI::InvalidURIError
      raise ArgumentError,'Choose an internal dashboard page'
    end
    def normalize(data)
      kind=data.fetch('kind')
      case kind
      when 'production'
        production=production!(data.fetch('id'));scene=production.studio_scenes.find(data['scene_id'] || production.studio_scenes.order(:id).first!.id)
        {'key'=>"production:#{production.id}",'kind'=>kind,'id'=>production.id,'scene_id'=>scene.id,'label'=>production.name.first(80)}
      when 'action'
        action=NevaehOsAction.where(user:@actor).find(data.fetch('id'))
        {'key'=>"action:#{action.id}",'kind'=>kind,'id'=>action.id,'label'=>"Task ##{action.id}"}
      when 'workers'
        {'key'=>kind,'kind'=>kind,'label'=>'Your workforce'}
      when 'guide'
        topic=data.fetch('topic','start').to_s
        Guide.tutorial(topic,actor:@actor)
        {'key'=>"guide:#{topic}",'kind'=>kind,'topic'=>topic,'label'=>'Guide & capabilities'}
      when 'learning'
        raise CanCan::AccessDenied unless Guide.allowed?('admin',@actor)
        {'key'=>kind,'kind'=>kind,'label'=>'Learning & study'}
      when 'page'
        path=page!(data.fetch('path'))
        {'key'=>"page:#{Digest::SHA256.hexdigest(path).first(16)}",'kind'=>kind,'path'=>path,'label'=>data.fetch('label','Application').to_s.first(80)}
      else raise ArgumentError,'Choose a production, task, workers, guide, learning or dashboard page'
      end
    end
    def update!(data)
      record=workspace
      record.with_lock do
        raise ActiveRecord::StaleObjectError.new(record,'stage update') unless record.lock_version==Integer(data.fetch('lock_version'))
        panels=record.panels.deep_dup
        case data.fetch('operation')
        when 'open'
          panel=normalize(data.fetch('panel'));panels.reject! { |row| row['key']==panel['key'] }
          raise ArgumentError,'Close a work tab before opening another (maximum eight)' if panels.size>=8
          panels<<panel;record.active_key=panel['key']
        when 'select'
          panel=panels.find { |row| row['key']==data.fetch('key') } || raise(ArgumentError,'Choose an open work tab')
          panel=normalize(panel.merge(data.slice('scene_id')));panels.map! { |row| row['key']==panel['key'] ? panel : row };record.active_key=panel['key']
        when 'close'
          panels.reject! { |row| row['key']==data.fetch('key') };record.active_key=panels.last&.fetch('key') if record.active_key==data['key']
        else raise ArgumentError,'Unknown stage operation'
        end
        record.update!(panels:panels)
      end
      read
    end
    def read
      record=workspace
      panels=record.panels.map do |handle|
        begin
          normalize(handle)
        rescue ActiveRecord::RecordNotFound,ArgumentError,CanCan::AccessDenied,LightekPwa::Policy::Denied
          handle.slice('key','kind').merge('label'=>'Unavailable work','unavailable'=>true)
        end
      end
      active=panels.find { |panel| panel['key']==record.active_key }
      content=active && !active['unavailable'] ? resolve(active) : nil
      projects=::Production.joins(:studio_project).where(studio_projects:{owner_id:@actor.id}).order(id: :desc).limit(30).filter_map do |production|
        begin
          Studio::Broadcasting::Access.authorize!(@actor,production.studio_project.site)
          {id:production.id,name:production.name}
        rescue LightekPwa::Policy::Denied,CanCan::AccessDenied
          nil
        end
      end
      {lock_version:record.lock_version,panels:panels,active_key:record.active_key,content:content,productions:projects}
    end
    def resolve(panel)
      case panel['kind']
      when 'production'
        production=production!(panel['id']);scene=production.studio_scenes.find(panel['scene_id']);site=production.studio_project.site_id
        operations=scene.studio_operations.order(id: :desc).limit(20)
        rehearsal=scene.studio_operations.where(capability:Studio::Director::Rehearsal::CAPABILITY).order(:id).last
        story=operations.find { |op| op.capability=='studio.direct.story' }
        previews=operations.select { |op| op.status=='completed' }.flat_map { |op| op.artifacts.where(kind:'video').map { |artifact| artifact.file.attached? && {id:artifact.id,name:artifact.filename,url:Rails.application.routes.url_helpers.rails_blob_path(artifact.file,only_path:true)} } }.select { |row| row }.first(4)
        {kind:'production',id:production.id,name:production.name,site_id:site,scene:{id:scene.id,name:scene.name,lock_version:scene.lock_version,fps:scene.settings.fetch('fps',24),frame_end:scene.settings.fetch('frame_end',1),script:scene.settings.dig('workspace','story','scriptDraft').to_s.first(50000)},
          scenes:production.studio_scenes.order(:id).map { |row| {id:row.id,name:row.name} },objects:scene.scene_objects.order(:id).limit(256).map { |object| {id:object.id,name:object.name,type:object.object_type,location:object.definition.fetch('location',[0,0,0]),character:!!(object.definition['character_profile'] || object.definition['director_speaker'] || object.definition['blocking_actor']),speaker:object.definition['director_speaker'],listener:object.definition.dig('story_relation','look_at'),takes:Array(object.definition['performance_takes'].presence || [object.definition['performance']].compact).map { |take| take.slice('start','duration','audio_asset_id') }} },
          previews:previews,worker_steps:story&.manifest&.fetch('stages',{}),rehearsal:rehearsal && Studio::Director::Rehearsal.receipt(rehearsal,actor:@actor),operations:operations.map { |op| {id:op.id,type:op.operation_type,status:op.status,error:op.error_message} },
          embed_url:"/dashboard/studio-broadcasting/workspace/#{scene.id}?site_id=#{site}&workspace=3d&nevaeh_embed=1"}
      when 'action'
        {kind:'action',receipt:Receipts.for(NevaehOsAction.where(user:@actor).find(panel['id']))}
      when 'workers'
        {kind:'workers',workers:NevaehAgentWorker.where(user:@actor).includes(:nevaeh_os_agent).order(id: :desc).limit(30).map { |worker| {id:worker.id,name:worker.name,agent:worker.nevaeh_os_agent.name,enabled:worker.enabled?,status:worker.runs.order(id: :desc).first&.execution_status} }}
      when 'guide' then {kind:'embed',embed_url:'/dashboard/nevaeh/guide?topic='+URI.encode_www_form_component(panel.fetch('topic','start'))}
      when 'learning' then {kind:'embed',embed_url:'/employee/nevaeh/factory'}
      when 'page' then {kind:'embed',embed_url:page!(panel['path'])}
      end
    end
    def instruction(text)
      record=workspace;panel=record.panels.find { |row| row['key']==record.active_key && row['kind']=='production' }
      return text unless panel
      production=production!(panel['id']);scene=production.studio_scenes.find(panel['scene_id'])
      if text.strip.match?(/\A(?:please )?(?:rehearse|preview) (?:this|the) scene[.!]?\z/i)
        return '/produce rehearse '+{'production_id'=>production.id,'scene_id'=>scene.id}.to_json
      end
      if text.strip.match?(/\A(?:please )?apply (?:that|the|this) rehearsal[.!]?\z/i)
        operation=scene.studio_operations.where(capability:Studio::Director::Rehearsal::CAPABILITY).order(:id).last || raise(ArgumentError,'Rehearse this scene first')
        return "/produce rehearsal_apply #{operation.id}"
      end
      if (match=text.strip.match(/\A(?:please )?(?:give|move) (.+?) (?:more space|farther (?:away )?from (.+?))[.!]?\z/i))
        cast=scene.scene_objects.select { |object| object.definition['character_profile'] || object.definition['director_speaker'] || object.definition['blocking_actor'] }
        actor=cast.find { |object| [object.name,object.definition['director_speaker']].compact.any? { |name| name.casecmp?(match[1]) } } || raise(ArgumentError,'Choose a character placed in the current scene')
        other=match[2] && cast.find { |object| [object.name,object.definition['director_speaker']].compact.any? { |name| name.casecmp?(match[2]) } }
        raise ArgumentError,'The listener was not found in this scene' if match[2] && !other
        other||=(cast-[actor]).min_by { |object| (object.definition.fetch('location',[0,0,0])[0]-actor.definition.fetch('location',[0,0,0])[0]).abs }
        position=actor.definition.fetch('location',[0,0,0]);target=other&.definition&.fetch('location',[0,0,0]) || [position[0]+1,position[1],position[2]]
        dx=position[0]-target[0];dy=position[1]-target[1];length=Math.hypot(dx,dy);dx=-1 if length<0.01;length=1 if length<0.01
        goal=[position[0]+dx/length,position[1]+dy/length]
        return '/produce rehearse '+{'production_id'=>production.id,'scene_id'=>scene.id,'goals'=>{actor.id.to_s=>goal}}.to_json
      end
      text
    end
    def save_script!(data)
      production=production!(data.fetch('production_id'));scene=production.studio_scenes.find(data.fetch('scene_id'))
      text=data.fetch('script')
      raise ArgumentError,'Use a script of at most 50,000 characters' unless text.is_a?(String) && text.length<=50000
      scene.with_lock do
        raise ActiveRecord::StaleObjectError.new(scene,'script save') unless scene.lock_version==Integer(data.fetch('lock_version'))
        Studio::Gatekeeper::Client.authorize!(capability:'studio.workspace.scene.save',subject:scene,context:{project_id:production.studio_project_id})
        work=scene.settings.fetch('workspace',{}).deep_dup;work['story']||={};work['story']['scriptDraft']=text
        scene.update!(settings:scene.settings.merge('workspace'=>work))
      end
      {scene_id:scene.id,lock_version:scene.lock_version}
    end
  end
end
