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
class Ability
  def initialize(actor) = @actor=actor
  def can?(_operation,_subject) = %w[admin super_admin].include?(@actor.role)
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
%w[models/nevaeh_os_action models/nevaeh_os_consent models/nevaeh_os_memory models/nevaeh_os_source models/nevaeh_os_agent models/nevaeh_capability
 services/nevaeh_os/resources services/nevaeh_os/command services/nevaeh_os/web_document services/nevaeh_os/executor services/nevaeh_os/dispatch services/nevaeh_os/worker
 services/gatekeeper/authorization_decision services/gatekeeper/authorization_service services/gatekeeper].each { |f| require File.join(ROOT,'app',f) }
class NevaehOsTest < Minitest::Test
  def setup
    [NevaehOsAction,NevaehOsAgent,NevaehOsMemory,NevaehOsConsent,NevaehOsSource,DymondDispatch::WorkItem,NevaehCapability,User].each(&:delete_all)
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
ActiveRecord::Schema.define { create_table(:test_sites) }
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
