# Existing real template compiler, Studio scenes, ownership, Nevaeh dispatch and
# FFmpeg audio probing. The unavailable stock speech binary is the IO fixture.
require_relative 'campaign_producer_checks'
%w[production_blueprints/registry production_blueprints/task_groups director/voice director/producer].each { |file| require File.join(ROOT,"app/services/studio/#{file}") }
require File.join(ROOT,'app/services/studio/publishers/registry')
require File.join(ROOT,'app/services/screenplay_engine/audio_synthesizer')
require File.join(ROOT,'app/jobs/studio_directed_voice_job')
class StudioDirectorProducerChecks < CampaignProducerChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  CampaignProducerChecks.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def directed(values={}, key: SecureRandom.uuid)
    Studio::Director::Producer.start!(actor: @alice, site: @site, values: {'name'=>'Episode One', 'template_key'=>'comedy'}.merge(values), request_key: key)
  end
  def voice_fixture
    ->(**args) do
      Studio::MediaProcess.run!(['ffmpeg','-v','error','-y','-f','lavfi','-i','sine=frequency=330:duration=0.8',args.fetch(:path)],timeout:30)
    end
  end
  def test_director_uses_long_form_recipes_bible_and_actual_camera_coverage_idempotently
    key = SecureRandom.uuid
    result = directed({'show_bible_key'=>'base/show_bible','episode_number'=>3}, key: key)
    production = Production.find(result.fetch('production_id'))
    assert_equal 'episode', production.kind
    assert_equal 1320, result.dig('director','total_seconds')
    assert_equal 22, production.studio_scenes.count
    assert_equal result['production_id'], directed({'show_bible_key'=>'base/show_bible','episode_number'=>3}, key: key)['production_id']
    scene = production.studio_scenes.order(:id).first
    assert_equal 3, scene.settings['episode_number']
    assert_equal 'base/show_bible', scene.settings['blender_presets'].last['key']
    assert scene.settings['blender_presets'].all? { |preset| preset['instance'].present? && preset['definition'].is_a?(Hash) }
    assert_operator scene.scene_objects.count, :>, 4
    shots = scene.settings.dig('shot_board','shots')
    assert_equal 4, shots.size
    assert_equal scene.scene_objects.where(object_type:'camera').pluck(:id).sort, shots.map { |shot| shot['camera_id'] }.sort
    assert_includes scene.settings.dig('workspace','story','scriptDraft'), 'Cold open'
    assert_equal 'scripted_series', result.dig('director','blueprint','blueprint_key')
    assert_equal 'requires_master_and_review', result.dig('director','deliveries',0,'status')
    assert_raises(ArgumentError) { directed({'name'=>'Changed'}, key:key) }
    assert_raises(ActiveRecord::RecordNotFound) { Studio::Director::Producer.find!(production.id,actor:@bob) }
    assert_equal 2520, Studio::NativeBlender::MediaPresets.resolve('production/network_procedural_42').dig('production','runtime_seconds')
    assert_equal 2880, Studio::NativeBlender::MediaPresets.resolve('production/serialized_drama_48').dig('production','runtime_seconds')
    assert Studio::Director::Producer.catalog.any? { |entry| entry['key']=='production/serialized_drama_48' }
  end
  def test_director_natural_request_uses_existing_dispatch_and_distinguishes_prepared_from_published
    text='make a 22 minute comedy episode called Family Business'
    chat = NevaehOs::Conversation.new(actor: @alice, host: @site.host)
    assert_equal 'planned', chat.ask(text:text,request_key:SecureRandom.uuid,mode:'reflect')['status']
    before = Production.count
    result = chat.ask(text:text,request_key:SecureRandom.uuid,mode:'operate')
    action = NevaehOsAction.find(result['action_id'])
    receipt = NevaehOs::Worker.perform('execute',{'action_id'=>action.id})
    assert_equal before+1, Production.count
    assert_equal 'prepared', receipt['status']
    assert_equal 'completed', NevaehOs::Receipts.for(action.reload)[:status]
    assert_equal 'not_dispatched', receipt.dig('director','readiness','publishing')
    assert_equal 'not_rendered', receipt.dig('director','readiness','episode_master')
    assert_equal 'studio.direct.production', NevaehOs::Agents.capability(action.command)
    assert_equal 'ready', chat.ask(text:'/produce catalog',request_key:SecureRandom.uuid)['status']
    assert_raises(ArgumentError) { NevaehOs::Command.parse('make a 42 minute comedy episode called Wrong duration') }
  end
  def test_director_voice_job_measures_audio_and_saves_editable_captions_without_duplicate_replay
    dialogue=[{'scene'=>1,'speaker'=>'Host','text'=>'Welcome to the show.','voice'=>'en-gb','speed'=>150}]
    result = directed({'dialogue'=>dialogue})
    op=StudioOperation.find(result['voice_operations'].first['id'])
    assert_equal 'dispatched', result['status']
    ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) { StudioDirectedVoiceJob.perform_now(op.id) }
    assert_equal 'completed', op.reload.status
    scene = op.studio_scene.reload
    asset = StudioAsset.find(op.manifest['asset_ids'].first)
    assert asset.metadata['synthetic_voice']
    assert_equal 'en-gb', asset.metadata['voice']
    assert_in_delta 0.8, asset.metadata['duration'], 0.02
    assert_equal asset.id, scene.settings.dig('timeline','clips',0,'asset_id')
    assert_includes scene.settings.dig('timeline','titles',0,'text'), 'Welcome to the show.'
    count=StudioAsset.count
    StudioDirectedVoiceJob.perform_now(op.id)
    assert_equal count, StudioAsset.count
    assert_equal 'prepared', Studio::Director::Producer.receipt(op.production,actor:@alice)['status']
  end
  def test_director_invalid_dialogue_rolls_back_and_stale_scene_is_preserved
    count=StudioProject.count
    assert_raises(ArgumentError) { directed({'dialogue'=>[{'scene'=>99,'text'=>'No scene'}]}) }
    assert_equal count, StudioProject.count
    assert_raises(ArgumentError) { directed({'show_bible_key'=>'camera/hero_push_in'}) }
    result=directed({'dialogue'=>[{'scene'=>1,'text'=>'Hello.'}]})
    op=StudioOperation.find(result['voice_operations'].first['id'])
    scene=op.studio_scene
    scene.update!(settings:scene.settings.merge('human_edit'=>true))
    ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) do
      assert_raises(ActiveRecord::StaleObjectError) { StudioDirectedVoiceJob.perform_now(op.id) }
    end
    assert_equal 'failed', op.reload.status
    assert scene.reload.settings['human_edit']
    assert_empty scene.settings.dig('timeline','clips')
  end
  def test_director_reuses_a_show_bible_as_the_episode_template_and_preserves_creator_edits
    key=SecureRandom.uuid
    values={'template_key'=>'show_bible/nerd_world_order_series'}
    result=directed(values,key:key)
    production=Production.find(result['production_id'])
    assert_equal 3,production.studio_scenes.count
    assert_in_delta 26,result.dig('director','total_seconds'),0.01
    scene=production.studio_scenes.order(:id).first
    assert_equal 1,scene.settings.dig('shot_board','shots').size
    settings=scene.settings.deep_dup
    settings['workspace']['story']['scriptDraft']='Creator revision'
    scene.update!(settings:settings)
    assert_equal production.id,directed(values,key:key)['production_id']
    assert_equal 'Creator revision',scene.reload.settings.dig('workspace','story','scriptDraft')
  end
  def test_director_real_stock_speech_creates_measured_voice_and_captions
    skip 'Set DIRECTOR_TEST_REAL_SPEECH=1 with espeak-ng installed' unless ENV['DIRECTOR_TEST_REAL_SPEECH']=='1'
    %w[en en-us en-gb ar].each do |voice|
      Dir.mktmpdir('stock-voice-') do |root|
        path=File.join(root,'voice.wav')
        text=voice=='ar' ? 'مرحبا بكم' : 'Welcome to Family Business.'
        ScreenplayEngine::AudioSynthesizer.synthesize!(text:text,path:path,voice:voice)
        assert_operator File.size(path), :>, 1000
      end
    end
    result=directed({'dialogue'=>[{'scene'=>1,'speaker'=>'Host','text'=>'Welcome to Family Business.'}]})
    op=StudioOperation.find(result['voice_operations'].first['id'])
    StudioDirectedVoiceJob.perform_now(op.id)
    assert_equal 'completed', op.reload.status
    asset=StudioAsset.find(op.manifest['asset_ids'].first)
    assert asset.metadata['duration'].between?(0.5,10)
    assert_equal 'en-us', asset.metadata['voice']
    assert_includes op.studio_scene.reload.settings.dig('timeline','titles',0,'text'), 'Family Business.'
  end
  def test_director_speech_process_uses_stdin_and_fixed_stock_voice_arguments
    Dir.mktmpdir('speech-args-') do |root|
      path=File.join(root,'voice.wav');calls=[]
      Studio::MediaProcess.stub(:run!,->(command,**options) { calls << [command,options];File.binwrite(path,'wav') }) do
        ScreenplayEngine::AudioSynthesizer.synthesize!(text:'--dangerous "quote" $(literal)',path:path,voice:'en-us',speed:155)
      end
      assert_equal '--stdin',calls.first[0][1]
      assert_equal '--dangerous "quote" $(literal)',calls.first[1][:stdin_data]
      refute_includes calls.first[0], '--dangerous "quote" $(literal)'
      assert_raises(ArgumentError) { ScreenplayEngine::AudioSynthesizer.synthesize!(text:'Hi',path:path,voice:'../../bad') }
      previous=ENV['STUDIO_TTS_BINARY'];ENV['STUDIO_TTS_BINARY']='/missing/speech-binary'
      assert_raises(ArgumentError) { ScreenplayEngine::AudioSynthesizer.synthesize!(text:'Hi',path:path) }
    ensure
      ENV['STUDIO_TTS_BINARY']=previous
    end
  end
end
