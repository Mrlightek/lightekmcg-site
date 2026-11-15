require_relative 'studio_director_producer_checks'
require File.join(ROOT,'app/services/nevaeh_os/presence')
module CanCan
  class AccessDenied < StandardError; end
end unless defined?(CanCan::AccessDenied)
require File.join(ROOT,'db/migrate/20261115235500_create_nevaeh_speeches')
CreateNevaehSpeeches.new.migrate(:up)
%w[app/models/nevaeh_speech app/services/studio/performance/audio_envelope app/services/nevaeh_os/speech app/jobs/nevaeh_os/speech_job app/helpers/nevaeh_help_helper app/controllers/dashboard/nevaeh_os_controller].each { |file| require File.join(ROOT,file) }
Rails.application.routes.append do
  post '/dashboard/nevaeh/speech',to:'dashboard/nevaeh_os#speech'
  get '/dashboard/nevaeh/speech/:id',to:'dashboard/nevaeh_os#speech_status'
  delete '/dashboard/nevaeh/speech/:id',to:'dashboard/nevaeh_os#speech_cancel'
  get '/dashboard/nevaeh/speech/:id/audio',to:'dashboard/nevaeh_os#speech_audio'
end
Rails.application.reload_routes!
class NevaehSpeechChecks < StudioDirectorProducerChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def setup
    super
    NevaehSpeech.delete_all
  end
  def speech(text:'Hello Marlon. We can work together.',key:SecureRandom.uuid)
    NevaehOs::Speech.request!(actor:@alice,text:text,request_key:key,voice:'en-us+f3')
  end
  def synthesize(record)
    if ENV['NEVAEH_TEST_REAL_SPEECH']=='1'
      NevaehOs::Speech.generate!(record)
    else
      ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,voice_fixture) { NevaehOs::Speech.generate!(record) }
    end
  end
  def test_request_is_owned_idempotent_bounded_and_not_prematurely_playable
    key=SecureRandom.uuid;record=speech(key:key)
    assert_equal record.id,speech(key:key).id
    assert_raises(ArgumentError) { speech(text:'Different response.',key:key) }
    assert_equal 'queued',record.status
    assert_nil NevaehOs::Speech.receipt(record)[:audio_url]
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::Speech.owned!(@bob,record.id) }
    2.times { speech }
    assert_raises(ArgumentError) { speech }
    assert_raises(ActiveRecord::RecordInvalid) { NevaehOs::Speech.request!(actor:@bob,text:'Text',request_key:SecureRandom.uuid,voice:'../../other') }
  end
  def test_natural_voice_is_default_and_real_model_produces_private_playable_audio
    record=NevaehOs::Speech.request!(actor:@alice,text:'Hello Marlon. Let us create something together.',request_key:SecureRandom.uuid)
    assert_equal 'nevaeh-natural',record.voice
    assert_equal 'kokoro_onnx',NevaehOs::Speech.receipt(record)[:engine]
    skip 'Set NEVAEH_TEST_NATURAL_VOICE=1 with the offline CPU model installed' unless ENV['NEVAEH_TEST_NATURAL_VOICE']=='1'
    Rails.stub(:root,Pathname(ROOT)) { NevaehOs::Speech.generate!(record) }
    assert_equal 'ready',record.reload.status,record.error
    assert record.audio.attached?
    assert record.mouth_frames.any? { |sample| sample['value']>0.1 }
    assert_equal "/dashboard/nevaeh/speech/#{record.id}/audio",NevaehOs::Speech.receipt(record)[:audio_url]
    client=session_for;client.get "/dashboard/nevaeh/speech/#{record.id}/audio",headers:headers
    assert_equal 200,client.response.status
    assert client.response.body.start_with?('RIFF')
    assert_equal 'nevaeh-natural',record.reload.voice
  end
  def test_production_natural_voice_keeps_text_private_and_attaches_container_input
    Dir.mktmpdir('neural-command-') do |root|
      path=File.join(root,'voice.wav');text='A private reply.'
      process=->(command,**options) do
        assert_equal ['docker','run'],command.first(2)
        assert_includes command,'--interactive'
        assert_equal 'none',command[command.index('--network')+1]
        refute_includes command,'--tty'
        refute_includes command,text
        assert_includes command,'/opt/lightek-voice/synthesize.py'
        assert_equal text,options[:stdin_data]
        assert_equal path.sub(root,'/work'),command[command.index('--output')+1]
        File.binwrite(path,'RIFFfixture')
      end
      Rails.env.stub(:production?,true) do
        Studio::NativeBlender::Runtime.stub(:image,'fixture/media') do
          Studio::MediaProcess.stub(:cpu_limit,'1') do
            Studio::MediaProcess.stub(:run!,process) do
              ScreenplayEngine::AudioSynthesizer.synthesize!(text:text,path:path,voice:'nevaeh-natural',speed:170)
            end
          end
        end
      end
      assert_raises(ArgumentError) { ScreenplayEngine::AudioSynthesizer.synthesize!(text:text,path:path,voice:'nevaeh-untrusted',speed:170) }
    end
  end
  def test_presence_distinguishes_queue_running_delay_and_completion_without_changing_jobs
    assert_equal 'idle',NevaehOs::Presence.for(@alice)[:state]
    result=directed({'dialogue'=>[{'scene'=>1,'text'=>'Hello.'}]})
    operation=StudioOperation.find(result['voice_operations'].first['id'])
    value=NevaehOs::Presence.for(@alice)
    assert_equal 'queued',value[:state];assert_equal 1,value[:counts][:queued]
    refute_includes value[:message],'running'
    assert_equal 'idle',NevaehOs::Presence.for(@bob)[:state]
    operation.update_column(:updated_at,11.minutes.ago)
    value=NevaehOs::Presence.for(@alice)
    assert_equal 'attention',value[:state];assert_includes value[:message],'still queued'
    assert_equal 'pending',operation.reload.status
    operation.update!(status:'running')
    assert_equal 'working',NevaehOs::Presence.for(@alice)[:state]
    operation.update!(status:'failed')
    assert_equal 'attention',NevaehOs::Presence.for(@alice)[:state]
    operation.update!(status:'completed')
    value=NevaehOs::Presence.for(@alice)
    assert_equal 'idle',value[:state];assert_includes value[:message],'finished'
    operation.update!(status:'awaiting_approval')
    assert_equal 'waiting',NevaehOs::Presence.for(@alice)[:state]
  end
  def test_real_speech_has_decodable_audio_actual_duration_and_mouth_samples
    record=speech
    synthesize(record)
    assert_equal 'ready',record.reload.status,record.error
    assert record.audio.attached?
    assert_operator record.duration,:>,0.1
    assert_operator record.duration,:<=,120
    assert record.mouth_frames.any? { |row| row['value']>0.1 }
    assert_equal 0,record.mouth_frames.first['time']
    assert_operator record.mouth_frames.last['time'],:<=,record.duration+0.04
    record.audio.blob.open do |file|
      info=JSON.parse(Studio::MediaProcess.run!(['ffprobe','-v','error','-show_entries','format=duration','-of','json',file.path]))
      assert_in_delta record.duration,Float(info['format']['duration']),0.02
      samples=Studio::MediaProcess.run!(['ffmpeg','-v','error','-i',file.path,'-t','1','-f','s16le','-']).b.unpack('s<*')
      assert_operator samples.map(&:abs).max,:>,50
    end
    attachment=record.audio.attachment.id
    NevaehOs::Speech.generate!(record)
    assert_equal attachment,record.reload.audio.attachment.id
  end
  def test_cancellation_failure_and_watchdog_never_report_playable_success
    pending=speech;NevaehOs::Speech.cancel!(@alice,pending.id);NevaehOs::Speech.generate!(pending)
    assert_equal 'cancelled',pending.reload.status;refute pending.audio.attached?
    running=speech
    callback=->(**args) { NevaehOs::Speech.cancel!(@alice,running.id);voice_fixture.call(**args) }
    ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,callback) { NevaehOs::Speech.generate!(running) }
    assert_equal 'cancelled',running.reload.status;refute running.audio.attached?
    failed=speech
    assert_raises(ArgumentError) do
      ScreenplayEngine::AudioSynthesizer.stub(:synthesize!,->(**_) { raise ArgumentError,'Speech engine unavailable' }) { NevaehOs::Speech.generate!(failed) }
    end
    assert_equal 'failed',failed.reload.status;assert_nil NevaehOs::Speech.receipt(failed)[:audio_url]
    stalled=speech;stalled.update!(status:'running',started_at:11.minutes.ago)
    NevaehOs::Speech.sweep!
    assert_equal 'failed',stalled.reload.status
  end
  def test_long_reply_is_explicitly_truncated_and_split_at_safe_boundaries
    text='An answer with a useful sentence. '*100
    record=speech(text:text)
    assert record.truncated
    assert_operator record.text.length,:<=,1800
    assert_equal record.text,NevaehOs::Speech.chunks(record.text).join
    assert NevaehOs::Speech.chunks(record.text).all? { |chunk| chunk.length<=900 }
    assert record.text.end_with?('.')
    assert_raises(ArgumentError) { speech(text:"Bad\0text") }
  end
  def test_authenticated_http_returns_private_audio_and_rejects_foreign_or_unready_clips
    record=speech;synthesize(record)
    client=session_for
    client.get "/dashboard/nevaeh/speech/#{record.id}",headers:headers
    assert_equal 200,client.response.status
    assert_equal 'volume',body(client)['mouth_mode']
    client.get "/dashboard/nevaeh/speech/#{record.id}/audio",headers:headers
    assert_equal 200,client.response.status
    assert client.response.body.start_with?('RIFF')
    assert_includes client.response.headers['Cache-Control'],'no-store'
    client.get "/dashboard/nevaeh/speech/#{record.id}/audio",headers:headers(@bob)
    assert_equal 404,client.response.status
    pending=speech
    client.get "/dashboard/nevaeh/speech/#{pending.id}/audio",headers:headers
    assert_equal 422,client.response.status
    client.get "/dashboard/nevaeh/speech/#{record.id}/audio",headers:{'Accept'=>'audio/wav'}
    assert_equal 401,client.response.status
  end
  def test_long_audio_keeps_its_opening_silence_and_late_speech_timestamps
    record=speech
    Dir.mktmpdir('long-voice-') do |root|
      path=File.join(root,'long.wav')
      Studio::MediaProcess.run!(['ffmpeg','-v','error','-y','-f','lavfi','-i','anullsrc=r=8000:cl=mono:d=68','-f','lavfi','-i','sine=frequency=220:duration=4','-filter_complex','[0:a][1:a]concat=n=2:v=0:a=1','-ac','1','-ar','8000',path])
      record.audio.attach(io:File.open(path),filename:'long.wav',content_type:'audio/wav',identify:false)
      frames=Studio::Performance::AudioEnvelope.call(record,first:0,duration:72)
      assert_equal 1800,frames.size
      assert_equal 0,frames.first['value']
      assert frames.select { |row| row['time']<67.9 }.all? { |row| row['value']==0 }
      assert frames.any? { |row| row['time']>68.1 && row['value']>0.5 }
      assert_in_delta 71.96,frames.last['time'],0.001
    end
  end
end
require 'action_controller/test_case'
class NevaehSpeechHttpChecks < ActionController::TestCase
  tests Dashboard::NevaehOsController
  def setup
    @actor=User.create!(role:'super_admin');@other=User.create!(role:'client')
    @request.headers['X-Pwa-Test-User']=@actor.id.to_s
    @routes=ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      post '/dashboard/nevaeh/speech',to:'dashboard/nevaeh_os#speech'
      get '/dashboard/nevaeh/speech/:id',to:'dashboard/nevaeh_os#speech_status'
      delete '/dashboard/nevaeh/speech/:id',to:'dashboard/nevaeh_os#speech_cancel'
    end
    @controller.allow_forgery_protection=true;@controller.set_request!(@request)
    @request.env['action_dispatch.request_forgery_protection_token']=nil
    @token=@controller.send(:form_authenticity_token)
    @request.set_header('HTTP_X_CSRF_TOKEN',@token)
  end
  def test_speech_mutations_require_csrf_and_keep_text_owned
    @request.set_header('HTTP_X_CSRF_TOKEN','bad')
    assert_raises(ActionController::InvalidAuthenticityToken) { post :speech,params:{text:'A private response.',request_key:'speech-http-123'},format: :json }
    @request.set_header('HTTP_X_CSRF_TOKEN',@token)
    post :speech,params:{text:'A private response.',request_key:'speech-http-123'},format: :json
    assert_response :success
    value=JSON.parse(response.body);record=NevaehSpeech.find(value['id'])
    assert_equal @actor.id,record.user_id;assert_equal 'queued',value['status'];assert_nil value['audio_url']
    @request.headers['X-Pwa-Test-User']=@other.id.to_s
    get :speech_status,params:{id:record.id},format: :json
    assert_response :not_found;refute_includes response.body,'A private response.'
  end
  def test_expired_clip_and_abandoned_queue_are_not_reused
    queued=NevaehOs::Speech.request!(actor:@actor,text:'Queued reply.',request_key:'speech-expire-123')
    queued.update_columns(created_at:11.minutes.ago)
    NevaehOs::Speech.sweep!
    assert_equal 'failed',queued.reload.status
    queued.update!(expires_at:1.second.ago)
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::Speech.owned!(@actor,queued.id) }
    NevaehOs::Speech.sweep!
    refute NevaehSpeech.exists?(queued.id)
  end
end
