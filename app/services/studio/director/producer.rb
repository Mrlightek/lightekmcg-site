# frozen_string_literal: true
require 'digest'
module Studio
  module Director
    # Connect the existing recovered presets, production blueprints and Director
    # to one owned, replayable production request. Preparation is not publication.
    class Producer
      TEMPLATE_ALIASES = {'comedy'=>'production/ensemble_comedy_22', 'procedural'=>'production/network_procedural_42', 'drama'=>'production/serialized_drama_48', 'documentary'=>'production/documentary_30'}.freeze
      def self.authorize!(actor, site)
        Studio::Broadcasting::Access.authorize!(actor.reload, site)
      end
      def self.catalog
        NativeBlender::MediaPresets.items.select { |row| %w[production_template show_bible production_preset].include?(row['category']) }
      end
      def self.normalize(raw)
        raise ArgumentError, 'Production inputs must be an object' unless raw.is_a?(Hash)
        data = raw.deep_stringify_keys
        raise ArgumentError, 'Unknown production input' unless (data.keys - %w[name template_key show_bible_key episode_number dialogue destinations]).empty?
        name = data.fetch('name').to_s.strip
        raise ArgumentError, 'Give the episode a name of 1–120 characters' unless data['name'].is_a?(String) && name.length.between?(1,120) && !name.match?(/[\x00-\x1f]/)
        key = TEMPLATE_ALIASES.fetch(data['template_key'], data['template_key'])
        recipe = NativeBlender::MediaPresets.resolve(key)
        raise ArgumentError, 'Choose a production template or show bible from /produce catalog' unless %w[production_template show_bible production_preset].include?(recipe['kind'] || recipe['type'])
        bible = data['show_bible_key'] && NativeBlender::MediaPresets.resolve(data['show_bible_key'])
        raise ArgumentError, 'Choose a show bible preset' if bible && (bible['kind'] || bible['type']) != 'show_bible'
        episode = data.fetch('episode_number',1)
        raise ArgumentError, 'Choose a positive episode number' unless episode.is_a?(Integer) && episode.between?(1,10000)
        destinations = data.fetch('destinations', %w[lightek_streaming])
        raise ArgumentError, 'Choose OTT, community, TikTok, Instagram or Facebook destinations' unless destinations.is_a?(Array) && destinations.any? && (destinations - Studio::Publishers::Registry::PUBLISHERS.keys).empty?
        lines = data.fetch('dialogue',[])
        raise ArgumentError, 'Provide at most 100 dialogue cues' unless lines.is_a?(Array) && lines.size <= 100
        lines = lines.map do |line|
          raise ArgumentError, 'Each dialogue cue must be an object' unless line.is_a?(Hash) && (line.keys - %w[scene speaker text start voice speed]).empty?
          line = line.deep_stringify_keys
          text = line.fetch('text').to_s
          speaker = line.fetch('speaker','Narrator').to_s
          index = line.fetch('scene')
          start = Float(line.fetch('start',0))
          raise ArgumentError, 'Use dialogue of 1–400 characters, a speaker and a valid scene number' unless line['text'].is_a?(String) && text.length.between?(1,400) && !text.match?(/[\x00-\x08\x0b-\x1f]/) && speaker.length.between?(1,80) && index.is_a?(Integer) && index.between?(1,100) && start.finite? && start.between?(0,570)
          {'scene'=>index, 'speaker'=>speaker, 'text'=>text, 'start'=>start, 'voice'=>Voice.voice!(line.fetch('voice','en-us')), 'speed'=>Voice.speed!(line.fetch('speed',155))}
        end
        {'name'=>name, 'template_key'=>key, 'show_bible_key'=>data['show_bible_key'], 'episode_number'=>episode, 'dialogue'=>lines, 'destinations'=>destinations.uniq}
      rescue KeyError => error
        raise ArgumentError, "Missing production input: #{error.key}"
      end
      def self.start!(actor:, site:, values:, request_key:)
        authorize!(actor, site)
        values = normalize(values)
        key = request_key.to_s
        raise ArgumentError, 'Use a request key of 16–100 letters, digits, underscores or hyphens' unless key.match?(/\A[a-zA-Z0-9_-]{16,100}\z/)
        fingerprint = Digest::SHA256.hexdigest(values.to_json)
        production = nil
        operations = []
        actor.with_lock do
          access = Studio::PwaAccess.new('user_id'=>actor.id, 'site_id'=>site.id)
          existing = StudioProject.find_by(owner_id: actor.id, request_key: key)
          if existing
            production = existing.productions.first!
            raise ArgumentError, 'This production key belongs to different inputs' unless existing.site_id == site.id && production.metadata.dig('director','input_fingerprint') == fingerprint
            operations = production.studio_operations.where(capability: 'studio.direct.voice', status: 'pending').to_a
            next
          end
          result = NativeBlender::PresetUse.call(access: access, payload: {'key'=>values['template_key'], 'mode'=>'new_project', 'name'=>values['name'], 'request_key'=>key})
          project = access.projects.find(result.fetch(:project_id))
          production = project.productions.first!
          scenes = project.studio_scenes.order(:id).to_a
          recipe = NativeBlender::MediaPresets.resolve(values['template_key'])
          bible = values['show_bible_key'] && NativeBlender::MediaPresets.resolve(values['show_bible_key'])
          sources = [values['template_key'], values['show_bible_key']].compact.map do |source_key|
            record = NativeBlender::MediaPresets.fetch(source_key)
            {'key'=>source_key, 'archive_sha256'=>record['source_sha256'], 'resolved_sha256'=>Digest::SHA256.hexdigest(NativeBlender::MediaPresets.resolve(source_key).to_json)}
          end
          raise ArgumentError, 'Choose a dialogue scene that exists in this production' unless values['dialogue'].all? { |line| line['scene'] <= scenes.size }
          raise ArgumentError, 'Use at most sixteen dialogue cues per scene' if values['dialogue'].group_by { |line| line['scene'] }.values.any? { |lines| lines.size > 16 }
          scenes.each_with_index do |scene,index|
            lines = values['dialogue'].select { |line| line['scene']==index+1 }
            prepare_scene!(scene, lines: lines, bible: bible, bible_key: values['show_bible_key'], episode: values['episode_number'])
            next if lines.empty?
            operations << scene.studio_operations.create!(studio_project: project, production: production, operation_type: 'voice_direction', provider: 'espeak', capability: 'studio.direct.voice', status: 'pending', intent: {'user_id'=>actor.id}, manifest: {'dialogue'=>lines}, metadata: {'draft_preview'=>true, 'scene_version'=>scene.reload.lock_version})
          end
          type = values['template_key'].include?('documentary') ? 'documentary' : values['template_key'].include?('music_video') ? 'music_video' : {'film'=>'film','series'=>'scripted_series','live'=>'live_broadcast','commercial'=>'commercial'}.fetch(recipe.dig('production','kind'),'scripted_series')
          blueprint = ProductionBlueprints::Registry.plan!(intent_key: 'production', production_type: type, start_mode_key: 'template', name: values['name'])
          director = {'version'=>1, 'input_fingerprint'=>fingerprint, 'inputs'=>values, 'sources'=>sources, 'show_bible'=>bible, 'blueprint'=>blueprint, 'task_groups'=>ProductionBlueprints::TaskGroups.build!(blueprint), 'scene_ids'=>scenes.map(&:id), 'total_seconds'=>scenes.sum { |scene| scene.settings.fetch('frame_end',1).to_f / scene.settings.fetch('fps',24) * scene.settings.fetch('fps_base',1) },
            'deliveries'=>values['destinations'].map { |destination| {'destination'=>destination, 'format'=>%w[tiktok instagram].include?(destination) ? 'portrait' : 'landscape', 'status'=>'requires_master_and_review'} },
            'readiness'=>{'staging'=>'prepared_from_template', 'camera_direction'=>'prepared_from_template', 'voices'=>operations.empty? ? 'dialogue_required' : 'queued', 'finished_performances'=>'requires_cast_and_review', 'episode_master'=>'not_rendered', 'publishing'=>'not_dispatched'}}
          production.update!(kind: 'episode', metadata: production.metadata.merge('director'=>director))
        end
        operations.each { |operation| StudioDirectedVoiceJob.perform_later(operation.id) }
        receipt(production, actor: actor)
      end
      def self.prepare_scene!(scene, lines:, bible:, bible_key:, episode:)
        settings = scene.settings.deep_dup
        settings['episode_number'] = episode
        if bible
          settings['blender_presets'] = Array(settings['blender_presets']) + [{'key'=>bible_key, 'definition'=>bible, 'title'=>bible['title'] || bible_key, 'instance'=>SecureRandom.hex(8), 'source_sha256'=>NativeBlender::MediaPresets.fetch(bible_key)['source_sha256']}]
        end
        brief = settings.dig('production_brief','segment') || {}
        settings['workspace'] ||= {}; settings['workspace']['story'] ||= {}
        settings['workspace']['story']['scriptDraft'] = ([brief['brief'] || brief['purpose'] || scene.name] + lines.map { |line| "#{line['start']}s · #{line['speaker']}: #{line['text']}" }).join("\n\n")
        coverage = Array(settings.dig('production_brief','coverage'))
        fps = settings.fetch('fps',24).to_f / settings.fetch('fps_base',1)
        cameras = scene.scene_objects.where(object_type: 'camera').index_by { |camera| camera.definition['production_shot_name'] || camera.name }
        if coverage.empty? && cameras.any?
          camera = cameras.values.first
          coverage = (1..settings.fetch('frame_end',1)).step(2400).map do |first|
            {'name'=>camera.definition['production_shot_name'] || camera.name, 'start_seconds'=>(first-1)/fps, 'duration_seconds'=>[2400,settings.fetch('frame_end')-first+1].min/fps}
          end
        end
        shots = coverage.each_with_index.map do |shot,index|
          first = (shot.fetch('start_seconds',0)*fps).round+1
          last = [first+(shot.fetch('duration_seconds',5)*fps).round-1, settings.fetch('frame_end',216000)].min
          {'id'=>"director-#{scene.id}-shot-#{index}", 'name'=>shot.fetch('name'), 'notes'=>brief['brief'].to_s.first(2000), 'camera_id'=>cameras.fetch(shot.fetch('name')).id, 'frame_start'=>first, 'frame_end'=>last, 'cast_ids'=>[]}
        end
        settings['shot_board'] = {'version'=>1, 'revision'=>1, 'shots'=>Studio::Shots::Board.normalize(scene, shots)} if shots.any?
        scene.update!(settings: settings)
      end
      def self.find!(id, actor:)
        production = ::Production.joins(:studio_project).where(studio_projects: {owner_id: actor.id}).find(id)
        raise ArgumentError, 'Choose a Director production' unless production.metadata['director']
        authorize!(actor, production.studio_project.site)
        production
      end
      def self.voice_operation!(id, actor:)
        operation = StudioOperation.where(capability: 'studio.direct.voice').find(id)
        find!(operation.production_id, actor: actor)
        operation
      end
      def self.retry_voice!(id, actor:)
        operation = voice_operation!(id, actor: actor)
        operation.with_lock do
          raise ArgumentError, 'Only failed voice operations can be retried' unless operation.status=='failed'
          operation.update!(status: 'pending', completed_at: nil, error_message: nil)
        end
        StudioDirectedVoiceJob.perform_later(operation.id)
        receipt(operation.production, actor: actor)
      end
      def self.receipt(production, actor:)
        find!(production.id, actor: actor)
        operations = production.studio_operations.where(capability: 'studio.direct.voice').order(:id).to_a
        status = operations.any? { |operation| operation.status == 'failed' } ? 'needs_attention' : operations.any? { |operation| %w[pending running].include?(operation.status) } ? 'dispatched' : 'prepared'
        director = production.metadata.fetch('director').deep_dup
        director['readiness']['voices'] = operations.empty? ? 'dialogue_required' : status == 'prepared' ? 'ready' : status
        {'production_id'=>production.id, 'status'=>status, 'director'=>director, 'voice_operations'=>operations.map { |operation| {'id'=>operation.id, 'status'=>operation.status, 'error'=>operation.error_message} },
          'links'=>[{'label'=>'Open episode in Studio', 'url'=>"/dashboard/studio-broadcasting/workspace/#{director['scene_ids'].first}?site_id=#{production.studio_project.site_id}&workspace=script"}],
          'text'=>"#{production.name}: #{status}. #{director['scene_ids'].size} editable scenes, #{director['total_seconds'].round} seconds planned, using existing production recipes and camera direction. Dialogue cues produce synthetic voice assets. Finished character performances, master assembly and publication still require their Studio workflows. Use /produce status #{production.id}."}
      end
    end
  end
end
