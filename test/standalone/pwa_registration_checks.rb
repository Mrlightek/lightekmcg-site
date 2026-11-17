# Real registration HTTP/controller, durable request, policy and job enqueue.
# Password validation and primary-session completion are host-engine boundaries.
require_relative 'pwa_launch_setup_checks'
require 'active_job'
require ROOT + '/app/jobs/application_job'
require ROOT + '/app/jobs/lightek_pwa/member_signup_job'
require ROOT + '/app/models/lightek_pwa/member_signup_request'
require ROOT + '/app/services/lightek_pwa/site_context'
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(File::NULL)
ActiveRecord::Schema.define do
  create_table(:lightek_pwa_member_signup_requests) do |t|
    t.references :site, null: false
    t.references :user, null: false, foreign_key: true
    t.string :state, default: 'queued', null: false
    t.timestamps
  end
  add_index :lightek_pwa_member_signup_requests, [:site_id, :user_id], unique: true
end
class User
  attr_accessor :first_name, :last_name, :password, :password_confirmation
end
class ApplicationController
  def self.allow_unauthenticated_access(**); end
  def self.skip_authorization_check; end
  def complete_primary_authentication_for(user)
    render json: {id: user.id, role: user.role}
  end
end
require ROOT + '/app/controllers/registrations_controller'
Rails.application.routes.append do
  get '/csrf', to: 'setup_csrf#show'
  get '/dashboard/pwa/revenue', to: 'setup_csrf#show', as: :dashboard_pwa_revenue
  get '/dashboard/vault', to: 'setup_csrf#show', as: :dashboard_vault
  post '/dashboard/pwa/revenue/launch-settings', to: 'dashboard/pwa_revenue#configure_launch', as: :configure_launch_dashboard_pwa_revenue
  post '/dashboard/pwa/revenue/payment-callbacks', to: 'dashboard/pwa_revenue#configure_webhook', as: :configure_webhook_dashboard_pwa_revenue
  post '/dashboard/pwa/revenue/verify-youtube', to: 'dashboard/pwa_revenue#verify_youtube', as: :verify_youtube_dashboard_pwa_revenue
  post '/commerce/stripe/webhook', to: 'commerce_stripe_webhooks#create', as: :commerce_stripe_webhook
  get '/sign_up', to: 'registrations#new', as: :sign_up
  post '/registrations', to: 'registrations#create'
end
Rails.application.reload_routes!

class PwaRegistrationTest < PwaLaunchSetupTest
  PwaLaunchSetupTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }
  def setup
    super
    Rails.cache.clear # Each HTTP fixture starts with an independent signup limit.
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end
  def register(return_to: '/lightek/index.html#/home', csrf: true)
    headers = {}
    if csrf
      @client.get '/csrf'
      assert_equal 200, @client.response.status, @client.response.body
      headers['X-CSRF-Token'] = JSON.parse(@client.response.body).fetch('csrf_token')
    end
    @client.post '/registrations', params: {return_to: return_to, user: {
      first_name: 'Launch', last_name: 'Fixture', email_address: 'signup@example.test',
      password: 'local-fixture-password', password_confirmation: 'local-fixture-password', role: 'super_admin'
    }}, headers: headers
    @client.response
  end
  def requests = LightekPwa::MemberSignupRequest.all
  def jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
  def test_imported_platform_site_signup_retains_owner_and_queues_member_backend
    LightekPwa::Policy.bind_platform!(site: @site, actor: @admin)
    assert_equal 200, register.status, @client.response.body
    user = User.find(JSON.parse(@client.response.body).fetch('id'))
    assert_equal 'client', user.role
    assert_equal @owner, @site.reload.tenant
    assert_equal 1, requests.count
    assert_equal [@site.id, user.id], [requests.first.site_id, requests.first.user_id]
    assert_equal 'queued', requests.first.state
    assert_equal 1, jobs.length
    assert_equal LightekPwa::MemberSignupJob, jobs.last.fetch(:job)
    assert_equal [@site.id, user.id], jobs.last.fetch(:args)
  end
  def test_original_super_admin_owned_site_still_queues_member_backend
    @site.update!(tenant: @admin)
    assert_equal 200, register.status
    assert_equal 1, requests.count
    assert_equal 1, jobs.length
  end
  def test_manifest_cannot_make_an_unbound_site_a_platform
    @site.update!(manifest: {'pwa_commerce'=>{'platform_operator_id'=>@admin.id}})
    assert_equal 200, register.status
    assert_empty requests
    assert_empty jobs
  end
  def test_revoked_operator_cannot_authorize_new_backend_requests
    LightekPwa::Policy.bind_platform!(site: @site, actor: @admin)
    @admin.update!(role: 'client')
    assert_equal 200, register.status
    assert_empty requests
    assert_empty jobs
  end
  def test_ordinary_registration_does_not_provision_a_pwa_backend
    LightekPwa::Policy.bind_platform!(site: @site, actor: @admin)
    assert_equal 200, register(return_to: '/dashboard').status
    assert_empty requests
    assert_empty jobs
  end
  def test_enqueue_failure_retains_the_transactional_request_for_recovery
    LightekPwa::Policy.bind_platform!(site: @site, actor: @admin)
    LightekPwa::MemberSignupJob.stub(:perform_later, ->(*) { raise IOError, 'queue unavailable' }) do
      assert_equal 200, register.status
    end
    assert_equal 1, requests.count
    assert_equal 'queued', requests.first.state
    assert_empty jobs
  end
  def test_csrf_rejects_registration_before_creating_user_or_request
    LightekPwa::Policy.bind_platform!(site: @site, actor: @admin)
    before = User.count
    assert_equal 422, register(csrf: false).status
    assert_equal before, User.count
    assert_empty requests
    assert_empty jobs
  end
end
