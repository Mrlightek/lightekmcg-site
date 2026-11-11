# frozen_string_literal: true
# Controlled SQLite integration: actual OS models, contracts, worker and Gatekeeper.
# Host engine dispatch and CanCan role policy are boundary adapters in this harness.
require 'minitest/autorun'
require 'minitest/mock'
require 'active_record'
require 'active_support/all'
require 'tmpdir'
require 'logger'
require 'ostruct'
# This container snapshot maps packaged system binaries to nobody. Simulate only
# their root ownership during activation; real binary execution and mode checks remain.
def with_packaged_binary_ownership
  original=File.method(:stat)
  File.stub(:stat,lambda { |path|
    stat=original.call(path)
    if %w[/usr/bin/ffmpeg /usr/bin/ffprobe].include?(path.to_s) && stat.uid==65534
      stat.define_singleton_method(:uid) { 0 }
    end
    stat
  }) { yield }
end
ROOT = File.expand_path('../..', __dir__)
ActiveRecord::Base.establish_connection(adapter:'sqlite3',database:':memory:')
ActiveRecord::Schema.verbose = false
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
class User < ApplicationRecord; end
module Rails
  def self.root = Pathname.new(ROOT)
  def self.logger = Logger.new(IO::NULL)
end
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :role }
  create_table(:nevaeh_capabilities) do |t|
    %i[name slug domain intent_name handler queue subject_type gatekeeper_capability].each { |field| t.string field }
    t.boolean :enabled, default:true
    t.integer :priority, default:5
    t.json :event_types, default:[]
    t.json :knowledge_article_ids, default:[]
    t.json :metadata, default:{}
  end
  create_table(:dymond_dispatch_work_items) do |t|
    t.string :subject_type
    t.integer :subject_id
    t.string :kind
    t.json :args
    t.string :status, default:'queued'
    t.json :result, default:{}
    t.text :error
  end
end
# Rails 7 compatibility for the available Ruby 3.2 harness only. Production keeps
# its Rails 8 migration and JSONB; SQLite receives the identical table definition.
ActiveRecord::ConnectionAdapters::TableDefinition.class_eval do
  def jsonb(*names, **options) = json(*names, **options)
end
migration = File.read(File.join(ROOT,'db/migrate/20261109090000_create_nevaeh_operating_system.rb')).sub('Migration[8.0]','Migration[7.2]')
eval(migration, TOPLEVEL_BINDING, 'nevaeh_os_test_migration')
CreateNevaehOperatingSystem.new.migrate(:up)
%w[20261109140000_create_nevaeh_application_adapters 20261109141000_connect_nevaeh_agent_workforce 20261109160000_create_nevaeh_watchers_and_events].each do |name|
  eval(File.read(File.join(ROOT,'db/migrate',name+'.rb')).sub('Migration[8.0]','Migration[7.2]'),TOPLEVEL_BINDING,name)
end
CreateNevaehApplicationAdapters.new.migrate(:up)
ConnectNevaehAgentWorkforce.new.migrate(:up)
CreateNevaehWatchersAndEvents.new.migrate(:up)
class Ability
  def initialize(actor) = @actor=actor
  def can?(_operation,_subject) = %w[admin super_admin].include?(@actor.role)
end
module NevaehOs
  class WatchPollJob
    def self.perform_later(*args) = args
  end
  class WatchEventJob
    def self.perform_later(id) = id
  end
  class AgentRunJob
    def self.perform_later(id) = id
  end
end
module DymondDispatch
  class WorkItem < ApplicationRecord
    self.table_name='dymond_dispatch_work_items'
  end
end
module LightekPwa
  class Policy
    class Denied < StandardError; end
  end
end
require File.join(ROOT,'app/services/lightek_community/workers/pwa')
require File.join(ROOT,'app/services/studio/workers/workspace')
require File.join(ROOT,'app/services/nevaeh_orchestration/native_contracts')
module NevaehIntelligences
  module StructuredExecution
    def self.authorize!(**) = raise('not expected')
  end
  module WorkOrder
    class Invalid < StandardError; end
  end
end
class NevaehWorkflow < ApplicationRecord; end
class Nevaeh
  def self.handle(**args)
    Gatekeeper.authorize_capability!(capability:args.fetch(:capability_hint),subject:args[:subject])
    item = DymondDispatch::WorkItem.create!(kind:args.fetch(:capability_hint),subject_type:args[:subject]&.class&.name,subject_id:args[:subject]&.id,args:args[:args])
    args[:subject] ? item : OpenStruct.new(work_item:item)
  end
end
%w[helpers/nevaeh_help_helper services/nevaeh_os/watch_contract services/nevaeh_os/watch_sensors services/nevaeh_os/watch_engine services/nevaeh_os/watch_reaction services/nevaeh_os/guide services/nevaeh_intelligences/software_library models/nevaeh_watcher models/nevaeh_watch_event models/nevaeh_agent_worker models/nevaeh_agent_run models/nevaeh_application_adapter models/nevaeh_os_action models/nevaeh_os_consent models/nevaeh_os_memory models/nevaeh_os_source models/nevaeh_os_agent models/nevaeh_capability
 services/nevaeh_os/agents services/nevaeh_os/agent_workforce services/nevaeh_os/ubuntu_packages services/nevaeh_os/applications services/nevaeh_os/process_runner services/nevaeh_os/rails_console services/nevaeh_os/resources services/nevaeh_os/command services/nevaeh_os/web_document services/nevaeh_os/executor services/nevaeh_os/dispatch services/nevaeh_os/worker
 services/gatekeeper/authorization_decision services/gatekeeper/authorization_service services/gatekeeper].each { |f| require File.join(ROOT,'app',f) }
class NevaehOsTest < Minitest::Test
  def setup
    [NevaehWatchEvent,NevaehWatcher,NevaehAgentRun,NevaehAgentWorker,NevaehApplicationAdapter,NevaehOsAction,NevaehOsAgent,NevaehOsMemory,NevaehOsConsent,NevaehOsSource,DymondDispatch::WorkItem,NevaehCapability,User].each(&:delete_all)
    @actor=User.create!(role:'super_admin')
    @other=User.create!(role:'client')
  end
  def command(text) = NevaehOs::Command.parse(text)
  def dispatch(text,key:'request-123456') = NevaehOs::Dispatch.submit!(actor:@actor,command:command(text),request_key:key)
  def execute(action) = NevaehOs::Worker.perform('execute',{'action_id'=>action.id})
  def test_natural_language_and_command_vocabulary
    assert_equal 'resources',command('/resources')['kind']
    assert_equal 'read',command('list workers')['operation']
    assert_equal 'paused',command('/pause worker 12')['status']
    assert_equal 'project',command('create a Studio project called Opening Night')['kind']
    assert_equal 'Opening Night',command('create a Studio project called Opening Night')['name']
    assert_equal 'ticket',command('open a ticket about missing captions')['kind']
    assert_equal 'model',command('/model 7 Hello Nevaeh')['kind']
    assert_equal 'capability',command('/execute studio.project.create {"name":"Night"}')['kind']
    assert_raises(ArgumentError) { command('/create agents {invalid}') }
    assert_raises(ArgumentError) { command('/update workers {}') }
    assert_raises(ArgumentError) { command('/system rm -rf /') }
    assert_equal 'search',command('do something magic')['kind']
  end
  def test_crud_uses_saved_action_and_real_gatekeeper_and_receipt
    action=dispatch('/create agents {"name":"Sage","role":"Strategist"}')
    assert_equal 'pending',action.status
    assert_equal 0,NevaehOsAgent.count
    assert_equal 1,DymondDispatch::WorkItem.count
    result=execute(action)
    assert_equal 'Sage',result['record']['name']
    assert_equal @actor.id,NevaehOsAgent.first.user_id
    assert_equal 'completed',action.reload.status
    2.times { execute(action) }
    assert_equal 1,NevaehOsAgent.count
    read=dispatch('/read agents',key:'read-request-123');execute(read)
    assert_equal ['Sage'],read.reload.result['records'].map { |r| r['name'] }
    update=dispatch("/update agents #{NevaehOsAgent.first.id} {\"name\":\"Muse\"}",key:'update-request-123');execute(update)
    assert_equal 'Muse',NevaehOsAgent.first.name
    remove=dispatch("/delete agents #{NevaehOsAgent.first.id}",key:'delete-request-123');execute(remove)
    assert_equal 0,NevaehOsAgent.count
  end
  def test_repeated_request_does_not_dispatch_twice_and_changed_inputs_are_rejected
    first=dispatch('/create agents {"name":"Sage"}')
    assert_equal first.id,dispatch('/create agents {"name":"Sage"}').id
    assert_equal 1,DymondDispatch::WorkItem.count
    assert_raises(ArgumentError) { dispatch('/create agents {"name":"Muse"}') }
    refute first.update(command:{'kind'=>'run','id'=>999})
  end
  def test_account_isolation_and_field_contract
    private_agent=NevaehOsAgent.create!(user:@other,name:'Private')
    assert_raises(ActiveRecord::RecordNotFound) { dispatch("/read agents #{private_agent.id}") }
    assert_raises(ArgumentError) { dispatch('/create agents {"name":"Sage","user_id":999}') }
    assert_raises(ArgumentError) { dispatch('/create users {"role":"super_admin"}') }
    assert_raises(ArgumentError) { dispatch('/create sources {"status":"reviewed"}') }
  end
  def test_disabled_capability_and_missing_subject_fail_closed
    NevaehOs::Dispatch.register!.update!(enabled:false)
    assert_raises(Gatekeeper::AuthorizationDenied) { dispatch('/create agents {"name":"Sage"}') }
    assert_raises(Gatekeeper::AuthorizationDenied) { Gatekeeper.authorize_capability!(capability:'nevaeh.os.execute') }
    assert_equal 0,DymondDispatch::WorkItem.count
    assert_equal 0,NevaehOsAgent.count
  end
  def test_registration_rejects_an_unexpected_worker_binding
    NevaehOs::Dispatch.register!.update!(handler:'Unexpected::Worker')
    assert_raises(ArgumentError) { dispatch('/create agents {"name":"Blocked"}') }
    assert_equal 0,DymondDispatch::WorkItem.count
  end
  def test_execution_rechecks_actor_permissions
    action=NevaehOsAction.create!(user:@actor,request_key:'revoke-request-1',command:{'kind'=>'run','id'=>42})
    NevaehOs::Dispatch.register!
    @actor.update!(role:'client')
    assert_raises(Gatekeeper::AuthorizationDenied) { execute(action) }
    assert_equal 'failed',action.reload.status
    assert_match(/administration required/,action.error)
  end
  def test_failed_resource_validation_rolls_back_and_records_failure
    action=dispatch('/create agents {"name":""}')
    assert_raises(ActiveRecord::RecordInvalid) { execute(action) }
    assert_equal 0,NevaehOsAgent.count
    assert_equal 'failed',action.reload.status
  end
  def test_consent_and_memory_belong_to_account_and_are_validated
    assert_raises(ActiveRecord::RecordInvalid) { NevaehOsConsent.create!(user:@actor,category:'secret') }
    consent=NevaehOsConsent.create!(user:@actor,category:'Preferences')
    refute consent.enabled?
    assert_equal 'Preferences',command('/remember Preferences: concise replies')['category']
    assert_raises(ArgumentError) { command('/remember unknown: bad') }
  end
  def test_scraper_rejects_local_metadata_reserved_and_ipv6_addresses
    %w[127.0.0.1 10.0.0.1 100.100.100.200 169.254.169.254 192.168.1.1 0.0.0.0 198.18.0.1 224.1.1.1 255.255.255.255 ::1 ::ffff:127.0.0.1].each do |ip|
      assert_raises(ArgumentError) { NevaehOs::WebDocument.public_address!(ip) }
    end
    assert_equal '8.8.8.8',NevaehOs::WebDocument.public_address!('8.8.8.8')
    %w[file:///etc/passwd http://example.com https://example.com:8443/ https://user:password@example.com/].each do |url|
      assert_raises(ArgumentError) { NevaehOs::WebDocument.fetch(url) }
    end
    Resolv.stub(:getaddresses,['127.0.0.1']) do
      assert_raises(ArgumentError) { NevaehOs::WebDocument.fetch('https://example.com/manual') }
    end
    Resolv.stub(:getaddresses,['8.8.8.8','10.0.0.1']) do
      assert_raises(ArgumentError) { NevaehOs::WebDocument.fetch('https://example.com/manual') }
    end
  end
end

require 'action_controller'
require 'action_controller/test_case'
module CanCan
  class AccessDenied < StandardError; end
end
class ApplicationController < ActionController::Base
  self.cache_store = ActiveSupport::Cache::MemoryStore.new
  before_action { head :unauthorized unless current_user }
  def current_user = User.find_by(id:session[:actor_id])
end
class Dashboard; end
require File.join(ROOT,'app/services/nevaeh_os/receipts')
require File.join(ROOT,'app/services/nevaeh_os/conversation')
require File.join(ROOT,'app/controllers/dashboard/nevaeh_os_controller')
class NevaehOsHttpTest < ActionController::TestCase
  tests Dashboard::NevaehOsController
  def setup
    @actor=User.create!(role:'super_admin')
    @other=User.create!(role:'client')
    @request.session[:actor_id]=@actor.id
    @routes=ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get '/dashboard/nevaeh/guide',to:'dashboard/nevaeh_os#guide',as: :dashboard_nevaeh_guide
      get '/dashboard/nevaeh/state',to:'dashboard/nevaeh_os#state'
      post '/dashboard/nevaeh/ask',to:'dashboard/nevaeh_os#ask'
      patch '/dashboard/nevaeh/consent',to:'dashboard/nevaeh_os#consent'
      post '/dashboard/nevaeh/memories',to:'dashboard/nevaeh_os#remember'
      delete '/dashboard/nevaeh/memories/:id',to:'dashboard/nevaeh_os#forget'
      get '/dashboard/nevaeh/actions/:id',to:'dashboard/nevaeh_os#action'
    end
    @controller.allow_forgery_protection=true
    # Generate a genuine Rails masked token bound to this test's session.
    @controller.set_request!(@request)
    @request.env['action_dispatch.request_forgery_protection_token']=nil
    @token=@controller.send(:form_authenticity_token)
    @request.set_header('HTTP_X_CSRF_TOKEN',@token)
  end
  def test_missing_csrf_rejects_mutation
    @request.set_header('HTTP_X_CSRF_TOKEN','bad')
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post :remember,params:{category:'Preferences',text:'blocked'},as: :json
    end
  end
  def test_memory_requires_consent_and_disable_erases_it
    post :remember,params:{category:'Preferences',text:'concise'},as: :json
    assert_response :not_found
    patch :consent,params:{category:'Preferences',enabled:true},as: :json
    assert_response :success
    post :remember,params:{category:'Preferences',text:'concise'},as: :json
    assert_response :success
    assert_equal ['concise'],NevaehOsMemory.where(user:@actor).pluck(:text)
    patch :consent,params:{category:'Preferences',enabled:false},as: :json
    assert_response :success
    assert_equal 0,NevaehOsMemory.where(user:@actor).count
  end
  def test_cannot_read_other_accounts_action_or_forget_their_memory
    action=NevaehOsAction.create!(user:@other,request_key:'private-receipt-1',command:{'kind'=>'run','id'=>1})
    memory=NevaehOsMemory.create!(user:@other,category:'Preferences',text:'private')
    get :action,params:{id:action.id},as: :json
    assert_response :not_found
    delete :forget,params:{id:memory.id},as: :json
    assert_response :not_found
    assert NevaehOsMemory.exists?(memory.id)
  end
  def test_ask_and_planning_mode_have_no_mock_fallback_or_execution
    post :ask,params:{q:'/help',request_key:'http-request-1'},as: :json
    assert_response :success
    assert_includes response.parsed_body['text'],'/resources'
    assert_nil response.parsed_body['ethics'].first
    post :ask,params:{q:'/create agents {"name":"Planned"}',request_key:'http-request-2',mode:2},as: :json
    assert_response :success
    assert_equal 'planned',response.parsed_body['status']
    refute NevaehOsAgent.exists?(name:'Planned')
  end
  def test_unauthenticated_request_is_rejected
    @request.session.delete(:actor_id)
    post :ask,params:{q:'/help',request_key:'http-request-3'},as: :json
    assert_response :unauthorized
  end
end

class NevaehOsWebDocumentTest < Minitest::Test
  class HTTPAdapter
    attr_accessor :ipaddr,:use_ssl,:open_timeout,:read_timeout,:write_timeout
    attr_reader :request_seen
    def initialize(response) = @response=response
    def start = yield(self)
    def request(value)
      @request_seen=value
      yield @response
    end
  end
  def response(content_type:'text/html',body:'<title>Manual</title><main><h1>Blender</h1><p>Model a cube.</p><script>steal()</script></main>')
    result=Net::HTTPOK.new('1.1','200','OK')
    result['content-type']=content_type
    result.define_singleton_method(:read_body) { |&block| block.call(body) }
    result
  end
  def test_public_fetch_pins_ip_strips_scripts_and_preserves_training_headings
    http=HTTPAdapter.new(response)
    Resolv.stub(:getaddresses,['8.8.8.8']) do
      Net::HTTP.stub(:new,http) do
        doc=NevaehOs::WebDocument.fetch('https://example.com/manual')
        assert_equal 'Manual',doc[:title]
        assert_includes doc[:body],'# Blender'
        assert_includes doc[:body],'Model a cube.'
        refute_includes doc[:body],'steal()'
        assert_equal Digest::SHA256.hexdigest(doc[:body]),doc[:sha256]
      end
    end
    assert_equal '8.8.8.8',http.ipaddr
    assert http.use_ssl
    assert_equal 'identity',http.request_seen['Accept-Encoding']
  end
  def test_redirect_target_is_revalidated_before_connecting
    result=Net::HTTPFound.new('1.1','302','Found');result['location']='https://127.0.0.1/private'
    http=HTTPAdapter.new(result)
    resolver=->(host) { host=='127.0.0.1' ? ['127.0.0.1'] : ['8.8.8.8'] }
    Resolv.stub(:getaddresses,resolver) do
      Net::HTTP.stub(:new,http) { assert_raises(ArgumentError) { NevaehOs::WebDocument.fetch('https://example.com/manual') } }
    end
  end
  def test_non_document_and_oversized_responses_are_rejected
    [response(content_type:'application/zip'),response(body:'x'*(NevaehOs::WebDocument::MAX_BYTES+1))].each do |result|
      Resolv.stub(:getaddresses,['8.8.8.8']) do
        Net::HTTP.stub(:new,HTTPAdapter.new(result)) { assert_raises(ArgumentError) { NevaehOs::WebDocument.fetch('https://example.com/manual') } }
      end
    end
  end
end

class NevaehOsNativeContractsTest < Minitest::Test
  def test_pwa_and_os_share_dynamic_studio_and_community_vocabulary
    Studio::Workers::Workspace::ACTIONS.each do |action|
      slug="studio.workspace.#{action.tr('_','.')}"
      assert NevaehOrchestration::NativeContracts.supported?(slug)
      assert_equal action,NevaehOrchestration::NativeContracts.resolve_worker_action!(slug)
      assert_equal "#{slug}.requested",NevaehOrchestration::NativeContracts.resolve_event_type!(slug)
    end
    LightekCommunity::Workers::Pwa::ACTIONS.each do |action|
      slug="community.#{action.delete_prefix('community_').tr('_','.')}"
      assert NevaehOrchestration::NativeContracts.supported?(slug)
      assert_equal action,NevaehOrchestration::NativeContracts.resolve_worker_action!(slug)
    end
    assert_equal 'send',NevaehOrchestration::NativeContracts.resolve_worker_action!('messages.send')
    assert_equal 'contribution_checkout',NevaehOrchestration::NativeContracts.resolve_worker_action!('susu.contribution.checkout')
    refute NevaehOrchestration::NativeContracts.supported?('arbitrary.ruby.call')
  end
end

# Native-worker handoff: actual PWA policy and shared contract, controlled engine
# database and queue boundary. It verifies stamped identity, not remote effects.
require File.join(ROOT,'app/services/lightek_pwa/policy')
module DymondSite
  class Site < ApplicationRecord
    self.table_name='test_sites'
  end
end
ActiveRecord::Schema.define { create_table(:test_sites) { |t| t.string :host } }
class DymondDispatch::WorkItem
  def done? = status=='done'
  def failed? = status=='failed'
end
class NevaehOsNativeHandoffTest < Minitest::Test
  def setup
    NevaehCapability.where(slug: ['nevaeh.os.execute','messages.list']).delete_all
  end
  def test_native_worker_payload_uses_saved_actor_and_host_site_and_tracks_receipt
    actor=User.create!(role:'super_admin')
    site=DymondSite::Site.create!
    NevaehCapability.create!(slug:'messages.list',name:'List messages',domain:'messages',intent_name:'messages_list',handler:'Messaging::Worker',queue:'default',priority:5,event_types:['messages.list.requested'])
    action=NevaehOs::Dispatch.submit!(actor:actor,request_key:'native-handoff-123',command:{'kind'=>'capability','intent'=>'messages.list','site_id'=>site.id,'origin'=>'https://lightekmcg.com','payload'=>{'user_id'=>999,'actor_id'=>999,'site_id'=>999}})
    NevaehOs::Worker.perform('execute',{'action_id'=>action.id})
    child=DymondDispatch::WorkItem.find(action.reload.result.fetch('work_item_id'))
    assert_equal 'list',child.args[0]
    assert_equal actor.id,child.args[1]['user_id']
    assert_equal actor.id,child.args[1]['actor_id']
    assert_equal site.id,child.args[1]['site_id']
    assert_equal 'dispatched',NevaehOs::Receipts.for(action)[:status]
    child.update!(status:'done',result:{'messages'=>[]})
    receipt=NevaehOs::Receipts.for(action)
    assert_equal 'completed',receipt[:status]
    assert_equal [],receipt[:downstream][:result]['messages']
  ensure
    NevaehCapability.where(slug:'messages.list').delete_all
  end
end

# Additional console policy adapter for the controlled host harness.
class ActiveRecord::Base
  def self.accessible_by(ability,operation=:read) = ability.can?(operation,self) ? all : none
end
ActiveRecord::Schema.define do
  create_table(:console_notes) { |t| t.string :title; t.string :secret_token }
end
class ConsoleNote < ApplicationRecord
  validates :title,presence:true
end
class NevaehOperatingConsoleTest < Minitest::Test
  def setup
    @admin=User.create!(role:'super_admin')
    @client=User.create!(role:'client')
  end
  def test_bare_capability_and_natural_susu_requests_are_commands
    %w[susu.list /susu.list /execute\ susu.list].each do |text|
      value=NevaehOs::Command.parse(text)
      assert_equal 'capability',value['kind']
      assert_equal 'susu.list',value['intent']
      assert_equal({},value['payload'])
    end
    assert_equal 'susu.list',NevaehOs::Command.parse('show my susus')['intent']
    assert_equal({'group_id'=>42},NevaehOs::Command.parse('susu.show {"group_id":42}')['payload'])
    assert_equal 'console',NevaehOs::Command.parse('/rails ConsoleNote.count')['kind']
    assert_equal 'ubuntu',NevaehOs::Command.parse('/ubuntu install ffmpeg')['kind']
    assert_equal 'ubuntu',NevaehOs::Command.parse('ubuntu.install {"package":"ffmpeg"}')['kind']
    assert_equal 12,NevaehOs::Command.parse('app.12.probe {"input":"test.wav"}')['adapter_id']
  end
  def test_bare_ruby_expression_uses_console_dispatch_and_current_authorization
    command=NevaehOs::Command.parse('ConsoleNote.count')
    assert_equal({'kind'=>'console','expression'=>'ConsoleNote.count'},command)
    assert NevaehOs::Executor.authorize_command!(actor:@admin,command:command)
    assert_raises(ArgumentError) { NevaehOs::Executor.authorize_command!(actor:@client,command:command) }
    rejected=NevaehOs::Command.parse('Kernel.system("id")')
    assert_raises(ArgumentError) { NevaehOs::Executor.authorize_command!(actor:@admin,command:rejected) }
    assert_equal 'capability',NevaehOs::Command.parse('susu.list')['kind']
  end
  def test_ruby_console_queries_create_update_destroy_and_redacts_secrets
    result=NevaehOs::RailsConsole.execute('ConsoleNote.create!(title: "First")',@admin)
    id=result['result']['id']
    assert_equal 'First',result['result']['title']
    ConsoleNote.find(id).update!(secret_token:'never-display')
    read=NevaehOs::RailsConsole.execute("ConsoleNote.find(#{id})",@admin)
    assert_equal '[REDACTED]',read['result']['secret_token']
    NevaehOs::RailsConsole.execute("ConsoleNote.find(#{id}).update!(title: \"Updated\")",@admin)
    assert_equal 'Updated',ConsoleNote.find(id).title
    rows=NevaehOs::RailsConsole.execute('ConsoleNote.where(title: "Updated").order(id: :desc).limit(2)',@admin)
    assert_equal [id],rows['result'].map { |v| v['id'] }
    assert NevaehOs::RailsConsole.schema('ConsoleNote',@admin)['fields'].none? { |v| v['name']=='secret_token' }
    NevaehOs::RailsConsole.execute("ConsoleNote.find(#{id}).destroy!",@admin)
    refute ConsoleNote.exists?(id)
  end
  def test_console_rejects_code_execution_raw_sql_unbounded_limits_and_domain_bypasses
    ['Kernel.system("id")','ConsoleNote.where("1=1")','ConsoleNote.limit(1000000)','ConsoleNote.all; system("id")','ConsoleNote.where(title: "#{system(\"id\")}")','ConsoleNote.delete_all','ConsoleNote.connection.execute("DROP TABLE users")','ConsoleNote.create!(secret_token: "secret")'].each do |expression|
      assert_raises(ArgumentError) { NevaehOs::RailsConsole.execute(expression,@admin) }
    end
    assert_raises(ArgumentError) { NevaehOs::RailsConsole.execute('ConsoleNote.count',@client) }
    assert_raises(ArgumentError) { NevaehOs::RailsConsole.execute('NevaehOsAction.create!(status: "completed")',@admin) }
    assert_raises(ActiveRecord::RecordInvalid) { NevaehOs::RailsConsole.execute('ConsoleNote.create!(title: "")',@admin) }
  end
  def test_ubuntu_and_application_control_require_host_super_administrator
    assert_raises(ArgumentError) { NevaehOs::UbuntuPackages.authorize!(@client) }
    assert_raises(ArgumentError) { NevaehOs::UbuntuPackages.authorize!(User.create!(role:'admin')) }
    assert_raises(ArgumentError) { NevaehOs::UbuntuPackages.call(operation:'install',package:'--allow-unauthenticated') }
    assert_raises(ArgumentError) { NevaehOs::UbuntuPackages.call(operation:'remove',package:'postgresql') }
  end
  def test_application_adapter_runs_real_unprivileged_ffmpeg_and_invalidates_on_edit
    adapter=NevaehApplicationAdapter.create!(user:@admin,package:'ffmpeg',name:'FFmpeg',operations:NevaehOs::Applications.recipes('ffmpeg'),documentation:{'binaries'=>['/usr/bin/ffmpeg','/usr/bin/ffprobe']})
    root=nil
    with_packaged_binary_ownership do
    NevaehOs::Applications.activate!(adapter,@admin)
    result=NevaehOs::Applications.run!(adapter:adapter,actor:@admin,operation:'version',inputs:{})
    assert_equal 0,result['exit_code']
    assert_includes result['stdout'],'ffmpeg version'
    root=NevaehOs::Applications.workspace(@admin)
    data=Array.new(800) { |i| (Math.sin(i*0.2)*1000).to_i }.pack('s<*')
    wave="RIFF"+[36+data.bytesize].pack('V')+"WAVEfmt "+[16,1,1,8000,16000,2,16].pack('VvvVVvv')+"data"+[data.bytesize].pack('V')+data
    File.binwrite(root.join('input.wav'),wave)
    probe=NevaehOs::Applications.run!(adapter:adapter,actor:@admin,operation:'probe',inputs:{'input'=>'input.wav'})
    assert probe['success']
    assert_equal 'audio',JSON.parse(probe['stdout'])['streams'].first['codec_type']
    transcode=NevaehOs::Applications.run!(adapter:adapter,actor:@admin,operation:'transcode',inputs:{'input'=>'input.wav','output'=>'converted.mp4'})
    assert transcode['success'],transcode['stderr']
    assert root.join('converted.mp4').file?
    assert_equal ['converted.mp4'],transcode['outputs']
    assert_raises(ArgumentError) { NevaehOs::Applications.checked_path(root,'../config/master.key',existing:true) }
    File.symlink('/etc/passwd',root.join('leak.txt'))
    assert_raises(ArgumentError) { NevaehOs::Applications.checked_path(root,'leak.txt',existing:true) }
    adapter.update!(operations:{'version'=>{'argv'=>['/usr/bin/ffmpeg','-version'],'inputs'=>{}}})
    assert_equal 'draft',adapter.status
    assert_raises(ArgumentError) { NevaehOs::Applications.run!(adapter:adapter,actor:@admin,operation:'version',inputs:{}) }
    end
  ensure
    FileUtils.remove_entry_secure(root) if root&.directory?
  end
  def test_agent_has_real_tasks_and_policies_restrict_its_capabilities
    sage=NevaehOs::Agents.resolve!('sage',@admin)
    assert_equal 'Sage',sage.name
    assert_equal sage.id,NevaehOs::Agents.resolve!('sage',@admin).id
    sage.update!(allowed_capabilities:['susu.list'])
    assert NevaehOs::Agents.authorize!({'kind'=>'capability','intent'=>'susu.list','agent_id'=>sage.id},@admin)
    assert_raises(ArgumentError) { NevaehOs::Agents.authorize!({'kind'=>'ubuntu','operation'=>'install','agent_id'=>sage.id},@admin) }
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::Agents.authorize!({'kind'=>'capability','intent'=>'susu.list','agent_id'=>sage.id},@client) }
    sage.update!(enabled:false)
    assert_raises(ArgumentError) { NevaehOs::Agents.authorize!({'kind'=>'capability','intent'=>'susu.list','agent_id'=>sage.id},@admin) }
  end
  def test_agent_worker_runs_are_idempotent_and_recheck_pause_before_dispatch
    sage=NevaehOs::Agents.resolve!('sage',@admin)
    worker=NevaehAgentWorker.create!(user:@admin,nevaeh_os_agent:sage,name:'Inspect own agents',command:{'kind'=>'resource','resource'=>'agents','operation'=>'read','attributes'=>{}})
    run=NevaehOs::AgentWorkforce.request!(worker:worker,actor:@admin,key:'manual-proof-1')
    assert_equal run.id,NevaehOs::AgentWorkforce.request!(worker:worker,actor:@admin,key:'manual-proof-1').id
    NevaehCapability.where(slug:'nevaeh.os.execute').delete_all
    NevaehOs::AgentWorkforce.execute!(run)
    assert run.reload.nevaeh_os_action_id
    assert_equal sage.id,run.nevaeh_os_action.command['agent_id']
    NevaehOs::AgentWorkforce.execute!(run)
    assert_equal 1,worker.runs.count
    second=NevaehOs::AgentWorkforce.request!(worker:worker,actor:@admin,key:'manual-proof-2')
    worker.update!(enabled:false)
    NevaehOs::AgentWorkforce.execute!(second)
    assert_equal 'blocked',second.reload.status
    assert_nil second.nevaeh_os_action_id
  end
  def test_scheduler_pauses_revoked_agents_and_assigns_one_durable_time_slot
    sage=NevaehOs::Agents.resolve!('sage',@admin)
    sage.update!(autonomy:'scheduled')
    worker=NevaehAgentWorker.create!(user:@admin,nevaeh_os_agent:sage,name:'Scheduled inspector',interval_minutes:5,command:{'kind'=>'resource','resource'=>'agents','operation'=>'read','attributes'=>{}})
    worker.update_columns(next_run_at:1.minute.ago)
    2.times { NevaehOs::AgentWorkforce.tick! }
    assert_equal 1,worker.runs.count
    assert worker.reload.next_run_at>Time.current
    sage.update!(enabled:false)
    worker.update_columns(next_run_at:1.minute.ago)
    NevaehOs::AgentWorkforce.tick!
    refute worker.reload.enabled?
    assert_nil worker.next_run_at
  end
end

class NevaehOsHttpTest
  def installed_susu
    NevaehCapability.where(slug:['susu.list','nevaeh.os.execute']).delete_all
    NevaehCapability.create!(slug:'susu.list',name:'My Susus',domain:'susu',intent_name:'susu_list',handler:'Susu::Workers::Pwa',queue:'default',priority:5,event_types:['susu.list.requested'])
    DymondSite::Site.create!(host:@request.host)
  end
  def test_exact_reported_bare_susu_command_is_dispatched_without_search
    installed_susu
    post :ask,params:{q:'susu.list',request_key:'bare-susu-request'},as: :json
    assert_response :success
    result=response.parsed_body
    assert_equal 'pending',result['status']
    refute_includes result['text'],'documentation'
    action=NevaehOsAction.find(result['action_id'])
    assert_equal 'susu.list',action.command['intent']
    assert_equal @actor.id,action.user_id
    NevaehOs::Worker.perform('execute',{'action_id'=>action.id})
    child=DymondDispatch::WorkItem.find(action.reload.result['work_item_id'])
    assert_equal 'list',child.args[0]
    assert_equal @actor.id,child.args[1]['user_id']
  end
  def test_delegated_agent_owns_a_real_run_and_nested_dispatch_receipt
    installed_susu
    post :ask,params:{q:'/delegate sage susu.list',request_key:'delegate-susu-request'},as: :json
    assert_response :success
    action=NevaehOsAction.find(response.parsed_body['action_id'])
    NevaehOs::Worker.perform('execute',{'action_id'=>action.id})
    run=NevaehAgentRun.find(action.reload.result['agent_run_id'])
    assert_equal 'Sage',run.nevaeh_agent_worker.nevaeh_os_agent.name
    NevaehOs::AgentWorkforce.execute!(run)
    assert_equal 'dispatched',run.reload.status
    child=run.nevaeh_os_action
    NevaehOs::Worker.perform('execute',{'action_id'=>child.id})
    item=DymondDispatch::WorkItem.find(child.reload.result['work_item_id'])
    item.update!(status:'done',result:{'groups'=>[{'id'=>3,'name'=>'Community fund'}]})
    receipt=NevaehOs::Receipts.for(action)
    assert_equal 'completed',receipt[:status]
    assert_equal 'Community fund',receipt[:downstream][:downstream][:result]['groups'].first['name']
  end
end
require File.join(ROOT,'app/services/susu/workers/pwa')
ActiveRecord::Schema.define do
  create_table(:susu_groups) { |t| t.string :name; t.integer :organizer_id }
  create_table(:susu_memberships) { |t| t.integer :susu_group_id; t.integer :user_id }
end
class SusuGroup < ApplicationRecord
  has_many :susu_memberships
end
class SusuMembership < ApplicationRecord; end
class NevaehSusuMembershipTest < Minitest::Test
  def test_list_scope_includes_only_organized_and_member_groups
    actor=User.create!(role:'client');other=User.create!(role:'client')
    owned=SusuGroup.create!(name:'Organized',organizer_id:actor.id)
    joined=SusuGroup.create!(name:'Joined',organizer_id:other.id)
    hidden=SusuGroup.create!(name:'Private',organizer_id:other.id)
    SusuMembership.create!(susu_group_id:joined.id,user_id:actor.id)
    worker=Susu::Workers::Pwa.new(action:'list',payload:{'user_id'=>actor.id})
    assert_equal [owned.id,joined.id].sort,worker.send(:accessible_groups).pluck(:id).sort
    refute_includes worker.send(:accessible_groups).pluck(:id),hidden.id
  end
end

class NevaehApplicationStorageTest < Minitest::Test
  def test_workspace_supports_native_shared_storage_symlink_but_not_user_path_symlinks
    actor=User.create!(role:'super_admin')
    Dir.mktmpdir do |directory|
      base=Pathname.new(directory);app=base.join('current');shared=base.join('shared')
      app.mkpath;shared.mkpath;File.symlink(shared,app.join('storage'))
      Rails.stub(:root,app) do
        root=NevaehOs::Applications.workspace(actor)
        assert_equal shared.join('nevaeh_applications',actor.id.to_s).to_s,root.to_s
        File.symlink('/etc/passwd',root.join('leak'))
        assert_raises(ArgumentError) { NevaehOs::Applications.checked_path(root,'leak',existing:true) }
      end
    end
  end
end

module Gatekeeper
  class LessonService
    def self.record!(**) = OpenStruct.new(id:999)
  end
end
class NevaehApplicationSetupTest < Minitest::Test
  def test_one_command_setup_imports_docs_activates_recipe_and_verifies_actual_application
    actor=User.create!(role:'super_admin')
    calls=[]
    package_service=lambda do |operation:,package:|
      calls << operation
      case operation
      when 'install' then {'package'=>package,'verified'=>true,'status'=>'installed'}
      when 'docs' then {'package'=>package,'binaries'=>['/usr/bin/ffmpeg','/usr/bin/ffprobe'],'documents'=>[{'path'=>'/usr/share/doc/ffmpeg/README','text'=>'FFmpeg media tools'}]}
      when 'show' then {'package'=>package,'installed_version'=>'fixture','summary'=>'Media tools','description'=>'FFmpeg media tools'}
      end
    end
    with_packaged_binary_ownership do
    NevaehOs::UbuntuPackages.stub(:call,package_service) do
      result=NevaehOs::Applications.setup!(actor,'ffmpeg')
      assert_equal 'active',result['status']
      assert result['verification']['success']
      assert_includes result['verification']['stdout'],'ffmpeg version'
      assert_equal %w[install docs show],calls
      adapter=NevaehApplicationAdapter.find(result['adapter_id'])
      assert_equal 'active',adapter.status
      assert_equal 'FFmpeg media tools',adapter.documentation['documents'].first['text']
      repeat=NevaehOs::Applications.setup!(actor,'ffmpeg')
      assert_equal adapter.id,repeat['adapter_id']
    end
    end
  ensure
    root=NevaehOs::Applications.workspace(actor) if actor
    FileUtils.remove_entry_secure(root) if root&.directory?
  end
end

class NevaehConsoleAuthorityTest < Minitest::Test
  def test_admin_console_cannot_promote_an_account_into_host_super_administrator
    administrator=User.create!(role:'admin')
    assert_raises(ArgumentError) { NevaehOs::RailsConsole.execute("User.find(#{administrator.id}).update!(role: \"super_admin\")",administrator) }
    assert_equal 'admin',administrator.reload.role
  end
end

class NevaehWatcherTest < Minitest::Test
  def setup
    @actor=User.create!(role:'super_admin')
    @agent=NevaehOs::Agents.resolve!('warden',@actor)
    NevaehCapability.where(slug:'nevaeh.os.execute').delete_all
  end
  def watcher(**extra)
    attributes={'name'=>'FFmpeg updates','kind'=>'ubuntu_package','target'=>{'package'=>'ffmpeg','refresh'=>false},'condition'=>'updated','response'=>'prepare','interval_minutes'=>60}.merge(extra.stringify_keys)
    NevaehOs::WatchEngine.create!(actor:@actor,attributes:attributes)
  end
  def poll(record,snapshot)
    NevaehOs::WatchSensors.stub(:snapshot,snapshot) { NevaehOs::WatchEngine.poll!(record.id,force:true) }
    record.reload
  end
  def versions(value) = {'ffmpeg'=>{'package'=>'ffmpeg','version'=>value}}
  def changed(record)
    poll(record,versions('1'));poll(record,versions('2'));record.events.order(:id).last
  end
  def test_first_poll_baselines_then_detects_each_real_transition_once
    record=watcher
    poll(record,versions('1'));assert record.initialized?;assert_equal 0,record.events.count
    poll(record,versions('2'));assert_equal 1,record.events.count
    poll(record,versions('2'));assert_equal 1,record.events.count
    poll(record,versions('1'));assert_equal 2,record.events.count
    assert_equal %w[updated updated],record.events.pluck(:change)
    assert_equal 2,record.events.pluck(:event_key).uniq.size
  end
  def test_new_catalog_entries_do_not_trigger_for_the_initial_catalog
    record=watcher(kind:'ubuntu_catalog',target:{'query'=>'video'},condition:'new')
    poll(record,versions('1'))
    poll(record,versions('2').merge('new-tool'=>{'package'=>'new-tool','version'=>'1'}))
    assert_equal ['new-tool'],record.events.pluck(:entity)
    assert_equal 'new',record.events.first.change
  end
  def test_prepare_is_read_only_and_explicit_apply_creates_one_agent_run
    record=watcher;event=changed(record)
    NevaehOs::UbuntuPackages.stub(:call,{'changes'=>[{'package'=>'ffmpeg','version'=>'2'}],'download_bytes'=>500}) do
      NevaehOs::WatchReaction.process!(event)
    end
    assert_equal 'prepared',event.reload.status
    assert_nil event.nevaeh_agent_run_id
    assert_equal 500,event.plan['installation']['download_bytes']
    NevaehOs::WatchReaction.process!(event,apply:true)
    assert_equal 'dispatched',event.reload.status
    run_id=event.nevaeh_agent_run_id
    assert_equal 'ubuntu',event.nevaeh_agent_run.snapshot['kind']
    assert_equal 'setup',event.nevaeh_agent_run.snapshot['operation']
    NevaehOs::WatchReaction.process!(event,apply:true)
    assert_equal run_id,event.reload.nevaeh_agent_run_id
  end
  def test_automatic_update_reuses_real_agent_execution_and_current_permissions
    record=watcher(response:'update');event=changed(record)
    NevaehOs::WatchReaction.process!(event)
    assert_equal 'dispatched',event.reload.status
    assert_equal @agent.id,event.nevaeh_agent_run.snapshot['agent_id']
    @actor.update!(role:'client')
    NevaehOs::AgentWorkforce.execute!(event.nevaeh_agent_run)
    assert_equal 'blocked',event.nevaeh_agent_run.reload.status
    assert_nil event.nevaeh_agent_run.nevaeh_os_action_id
  end
  def test_rule_edit_rebaselines_and_cannot_upgrade_an_old_event_policy
    record=watcher;event=changed(record)
    record.update!(response:'update')
    refute record.initialized?
    NevaehOs::WatchReaction.process!(event)
    assert_equal 'blocked',event.reload.status
    assert_match(/definition changed/,event.error)
    assert_nil event.nevaeh_agent_run_id
  end
  def test_paused_owner_or_agent_blocks_observation_and_pending_reaction
    record=watcher;event=changed(record)
    @agent.update!(enabled:false)
    NevaehOs::WatchReaction.process!(event)
    assert_equal 'blocked',event.reload.status
    assert_raises(ArgumentError) { poll(record,versions('3')) }
    assert_equal 'paused',record.reload.status
  end
  def test_three_sensor_failures_pause_without_consuming_the_baseline
    record=watcher
    3.times do
      NevaehOs::WatchSensors.stub(:snapshot,->(*) { raise ArgumentError,'Network unavailable' }) do
        assert_raises(ArgumentError) { NevaehOs::WatchEngine.poll!(record.id,force:true) }
      end
    end
    record.reload
    assert_equal 'paused',record.status
    assert_equal 3,record.failures
    refute record.initialized?
    assert_equal({},record.baseline)
  end
  def test_lease_and_revision_prevent_competing_or_stale_polls
    record=watcher
    record.update!(lease_token:'in-flight',lease_expires_at:10.minutes.from_now)
    assert_equal 'busy',NevaehOs::WatchEngine.poll!(record.id,force:true)
    record.update!(lease_token:nil,lease_expires_at:nil)
    sensor=->(_) { record.reload.update!(status:'paused');versions('2') }
    NevaehOs::WatchSensors.stub(:snapshot,sensor) { assert_equal 'superseded',NevaehOs::WatchEngine.poll!(record.id,force:true) }
    assert_equal 0,record.events.count
    refute record.reload.initialized?
  end
  def test_named_worker_command_template_is_data_bound_and_idempotent
    record=watcher(response:'command',command_template:{'kind'=>'ticket','text'=>'@event.entity'})
    event=changed(record)
    # Ticket permission is a real boundary adapter here; avoid creating a ticket.
    NevaehOs::Executor.stub(:authorize_command!,@actor) do
      NevaehOs::AgentWorkforce.stub(:request!,->(worker:,actor:,key:) { worker.runs.create!(actor:actor,request_key:key,snapshot:worker.command) }) do
        NevaehOs::WatchReaction.process!(event)
      end
    end
    assert_equal 'ffmpeg',event.reload.nevaeh_agent_run.snapshot['text']
    assert_equal 'dispatched',event.status
    assert_equal 'literal #{bad}',NevaehOs::WatchContract.expand('literal #{bad}',{})
    assert_raises(ArgumentError) { NevaehOs::WatchContract.expand('@event.untrusted',{}) }
  end
  def test_watcher_contract_rejects_unknown_sources_credentials_and_unbounded_rules
    [{kind:'github_repository',target:{'repository'=>'owner/repo/../../evil','branch'=>'main'}},
     {kind:'github_account',target:{'owner'=>'owner','account_type'=>'bad'}},
     {kind:'ubuntu_package',target:{'package'=>'--unsafe'}},
     {kind:'ubuntu_package',target:{'package'=>'ffmpeg','token'=>'never-store'}},
     {kind:'github_account',target:{'owner'=>'owner','account_type'=>'user'},response:'update'}].each do |attributes|
      assert_raises(ActiveRecord::RecordInvalid) { watcher(**attributes) }
    end
  end
  def test_github_sensors_encode_branch_names_and_observe_account_creation
    record=watcher(kind:'github_repository',target:{'repository'=>'Mrlightek/lightekmcg-site','branch'=>'feature/new'},condition:'updated')
    paths=[]
    NevaehOs::WatchSensors.stub(:github_get,->(path,_) { paths << path;{'commit'=>{'sha'=>'abc'}} }) do
      data=NevaehOs::WatchSensors.snapshot(record)
      assert_equal 'abc',data['Mrlightek/lightekmcg-site']['version']
    end
    assert_includes paths.first,'feature%2Fnew'
    account=watcher(kind:'github_account',target:{'owner'=>'Mrlightek','account_type'=>'user'},condition:'new')
    NevaehOs::WatchSensors.stub(:github_get,[{'id'=>123,'full_name'=>'Mrlightek/new-project','default_branch'=>'main'}]) do
      assert_equal ['123'],NevaehOs::WatchSensors.snapshot(account).keys
    end
  end
end

class NevaehGuideTest < Minitest::Test
  def setup
    @actor=User.create!(role:'super_admin')
    @client=User.create!(role:'client')
  end
  def test_every_tutorial_has_actionable_steps_examples_and_permission_filtering
    topics=NevaehOs::Guide.topics(actor:@actor)
    assert_equal 13,topics.size
    topics.each do |topic|
      document=NevaehOs::Guide.tutorial(topic[:id],actor:@actor)
      assert document[:body].start_with?('# ')
      assert_operator document[:body].length,:>,800
      assert_includes document[:body],'## '
    end
    refute NevaehOs::Guide.topics(actor:@client).any? { |row| row[:id]=='ubuntu' }
    assert_raises(ArgumentError) { NevaehOs::Guide.tutorial('console',actor:@client) }
    assert_raises(ArgumentError) { NevaehOs::Guide.tutorial('../../etc/passwd',actor:@actor) }
  end
  def test_new_installed_capabilities_automatically_get_visible_reference_and_schema_gap
    cap=NevaehCapability.create!(slug:'guide.example.new',name:'Example documented registration',domain:'example',intent_name:'guide_example_new',handler:'ExampleWorker',queue:'default',priority:5)
    reference=NevaehOs::Guide.capability(cap.slug,actor:@actor)
    assert_equal 'schema_needed',reference[:coverage]
    assert_equal 'adapter_needed',reference[:availability]
    %i[permission how_to verification recovery example topic].each { |key| assert reference[key].present?,key }
    assert_raises(ArgumentError) { NevaehOs::Guide.capability(cap.slug,actor:@client) }
    cap.update!(metadata:{'input_schema'=>{'record_id'=>{'type'=>'integer'}}})
    updated=NevaehOs::Guide.capability(cap.slug,actor:@actor)
    assert_equal 'fields',updated[:coverage]
    assert_equal({'record_id'=>'integer'},updated[:inputs])
  ensure
    cap&.destroy!
  end
  def test_builtin_and_resource_guides_cover_host_watchers_agents_and_actual_operations
    catalog=NevaehOs::Guide.catalog(actor:@actor)
    %w[ubuntu.setup watcher.create watcher.apply agents.list agent.schedule rails.console].each do |key|
      assert catalog.any? { |row| row[:key]==key },key
    end
    refute catalog.any? { |row| row[:key]=='resource.watchers.create' }
    refute catalog.any? { |row| row[:key]=='resource.sources.create' }
    assert catalog.any? { |row| row[:key]=='resource.sources.destroy' }
    refute NevaehOs::Guide.catalog(actor:@client).any? { |row| row[:key]=='ubuntu.setup' }
  end
end

class NevaehOsHttpTest
  def test_guide_json_and_in_chat_tutorials_share_the_installed_reference
    get :guide,params:{topic:'watchers'},as: :json
    assert_response :success
    payload=response.parsed_body
    assert_equal 'watchers',payload['tutorial']['id']
    assert payload['capabilities'].any? { |row| row['key']=='watcher.create' }
    post :ask,params:{q:'/guide agents',request_key:'guide-agents-request'},as: :json
    assert_response :success
    assert_includes response.parsed_body['text'],'/delegate sage susu.list'
    assert_equal '/dashboard/nevaeh/guide?topic=agents',response.parsed_body['guide_url']
  end
  def test_client_cannot_read_host_tutorial_or_create_watchers
    @request.session[:actor_id]=@other.id
    get :guide,params:{topic:'watchers'},as: :json
    assert_response :unprocessable_entity
    post :ask,params:{q:'/watch create {"name":"Forbidden","kind":"ubuntu_sources","target":{}}',request_key:'forbidden-watcher-request'},as: :json
    assert_response :unprocessable_entity
    refute NevaehWatcher.where(user:@other).exists?
  end
  def test_rendered_guide_has_live_reference_examples_and_escaped_titles
    @controller.prepend_view_path(File.join(ROOT,'app/views'))
    @controller.class.helper(Module.new do
      def dashboard_nevaeh_guide_path(**values) = '/dashboard/nevaeh/guide?'+URI.encode_www_form(values)
    end)
    unsafe=NevaehCapability.create!(slug:'guide.escaping.example',name:'<script>window.BAD_GUIDE=1</script>',domain:'example',intent_name:'guide_escaping_example',handler:'ExampleWorker',queue:'default',priority:5)
    get :guide,params:{topic:'watchers'},format: :html
    assert_response :success
    assert_includes response.body,'Watch changes and respond automatically'
    assert_includes response.body,'Live capability reference'
    assert_includes response.body,'/watch create'
    assert_includes response.body,'Input schemas to publish'
    FileUtils.mkdir_p(File.join(ROOT,'tmp'))
    assert_includes response.body,'&lt;script&gt;window.BAD_GUIDE=1&lt;/script&gt;'
    refute_includes response.body,'<script>window.BAD_GUIDE=1</script>'
    File.write(File.join(ROOT,'tmp/nevaeh-guide-preview.html'),response.body)
    unsafe.destroy!
  end
end
