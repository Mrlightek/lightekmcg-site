# Real content schema, shared writer, authoring/review services, native HTTP and
# queued-content guards. Studio project allocation and provider IO are boundary
# fixtures; real StudioProduction and production publication services execute.
require_relative 'daily_growth_checks'
ActiveRecord::Schema.define do
  create_table(:lightek_marketing_deliveries) { |t| t.references :campaign; t.references :contact; t.string :status, default: 'pending'; t.integer :mail_message_id; t.string :error_message; t.timestamps }
  create_table(:lightek_marketing_social_connections) { |t| t.references :site; t.string :provider; t.string :account_label; t.string :credential_key; t.string :publish_endpoint; t.boolean :enabled, default: true }
  create_table(:lightek_marketing_social_posts) { |t| t.references :campaign; t.references :connection; t.string :status, default: 'pending'; t.string :remote_id; t.string :submission_status; t.string :error; t.datetime :published_at; t.timestamps }
  create_table(:lightek_mail_messages) { |t| t.references :account }
  create_table(:content_test_scenes) { |t| t.json :settings, default: {} }
end
require ROOT.join('db/migrate/20261115160000_add_campaign_content_review')
AddCampaignContentReview.new.migrate(:up)
LightekMarketing::Campaign.reset_column_information
%w[content_variant delivery social_connection social_post].each { |file| require ROOT.join("app/models/lightek_marketing/#{file}") }
%w[editorial_direction writing_engine].each { |file| require ROOT.join("app/services/nevaeh_intelligences/#{file}") }
%w[content_workbench audience_dispatch email_delivery social_dispatch studio_production].each { |file| require ROOT.join("app/services/lightek_marketing/#{file}") }
%w[campaign_delivery_job scheduled_campaign_job].each { |file| require ROOT.join("app/jobs/lightek_marketing/#{file}") }
require ROOT.join('app/controllers/dashboard/campaign_content_controller')
Dashboard::CampaignContentController.prepend_view_path ROOT.join('app/views')
Dashboard::CampaignContentController.layout false
# Add the existing publishing destination to the fixture router.
SalesHarness.routes.draw do
  %w[campaign_performance website_audits publication_calendar campaign_content growth lifecycle people sales_quotes sales].each { |file| eval(ROOT.join("config/routes/#{file}.rb").read, binding) }
  get '/orders', to: 'dashboard/sales#index', as: :dashboard_commerce_orders
  get '/customers/history', to: 'dashboard/sales#index', as: :history_dashboard_customers
  get '/csrf', to: 'dashboard/settings_home#csrf'
  post '/website-inquiry', to: 'website_template_inquiries#create'
  get '/shop', to: 'commerce#index', as: :commerce_shop
  post '/shop/add', to: 'commerce#add'
  post '/shop/checkout', to: 'commerce#checkout'
  eval(ROOT.join('config/routes/commerce_embedded_checkout.rb').read, binding)
  get '/campaigns/:id/edit', to: 'dashboard/marketing_campaigns#edit', as: :edit_dashboard_marketing_campaign
  post '/campaigns/:id/studio', to: 'dashboard/marketing_campaigns#studio', as: :studio_dashboard_marketing_campaign
  patch '/campaigns/:id', to: 'dashboard/marketing_campaigns#update', as: :dashboard_marketing_campaign
  get '/campaigns', to: 'dashboard/marketing_campaigns#index', as: :dashboard_marketing_campaigns
  get '/unsubscribe/:token', to: 'dashboard/campaign_content#index', as: :unsubscribe_marketing_subscription
  get '/social-connections', to: 'dashboard/campaign_content#index', as: :dashboard_social_connections
  %w[business_hub website_designs media_studio commerce customers pwa].each do |name|
    get "/workspace/#{name}", to: 'dashboard/sales#index', as: "dashboard_#{name}"
  end
end
module LightekMail::Submission
  class Unavailable < StandardError; end
  def self.create!(**) = raise('Unexpected provider delivery')
end
class LightekMail::Message < ApplicationRecord
  self.table_name = 'lightek_mail_messages'
end
LightekMarketing::Contact.signed_id_verifier = ActiveSupport::MessageVerifier.new('content-contact-test-only-' * 8)
class LightekMail::Account
  def sending_ready? = true
end
module LightekMarketing::MetaConnectionHealth
  def self.check!(**) = true
end
module LightekMarketing::SocialProviders
  def self.publish!(**) = raise('Unexpected social provider call')
end
class ContentTestScene < ApplicationRecord
  self.table_name = 'content_test_scenes'
end
module Studio
  module Broadcasting
    module Access
      def self.authorize!(*args) = true
    end
  end
  module Workers
    module Workspace
      def self.perform(*args) = raise('Unexpected Studio allocation')
    end
  end
  class PwaAccess
    def initialize(*) = nil
    def scene!(id) = ContentTestScene.find(id)
  end
end
SalesCrmChecks.prepend(Module.new do
  def setup
    [LightekMarketing::Delivery, LightekMarketing::SocialPost, LightekMarketing::SocialConnection, ContentTestScene].each(&:delete_all)
    super
  end
end)
class CampaignContentChecks < DailyGrowthChecks
  def self.runnable_methods = instance_methods.grep(/^test_content_/).map(&:to_s)
  def workbench(actor = @owner) = LightekMarketing::ContentWorkbench.new(actor: actor, site: @site)
  def variations(key: 'content-generation-1', tracking_link: @link)
    brief(voice: 'Tone: direct') unless LightekGrowth::Brief.exists?(site: @site)
    workbench.generate!(campaign_id: @campaign.id, request_key: key, tracking_link_id: tracking_link&.id)
  end
  def approved
    variant = variations.first
    workbench.approve!(id: variant.id, version: variant.lock_version)
    @campaign.reload
    variant.reload
  end
  def connection
    LightekMarketing::SocialConnection.create!(site: @site, provider: 'facebook', account_label: 'Page', credential_key: 'fixture', publish_endpoint: 'https://graph.facebook.com')
  end
  def test_content_three_real_writer_variations_are_attributed_editable_and_retry_safe
    rows = variations
    assert_equal %w[offer problem benefit], rows.map(&:angle)
    assert_equal 3, rows.size
    assert_equal rows.map(&:id), variations.map(&:id)
    assert_equal 3, LightekMarketing::ContentVariant.count
    assert_equal 'draft', @campaign.reload.status
    refute @campaign.content_review_required?
    assert rows.map(&:message).uniq.size == 3
    assert_includes rows.first.message, 'Managed websites'
    assert_includes rows.first.message, 'One place to run the business'
    assert_equal 'direct', rows.first.source_snapshot.dig('editorial', 'applied', 'tone')
    assert_includes rows.first.cta_url, '/g/'
    assert_equal @link.id, rows.first.source_snapshot['tracking_link_id']
    assert_equal 'rules', rows.first.source_snapshot['provider']
    edited = workbench.update!(id: rows.first.id, version: 0, values: {headline: 'Reviewed headline', message: 'Reviewed customer promise', status: 'approved'})
    assert_equal 'draft', edited.status
    assert_equal 1, edited.lock_version
    assert_raises(ActiveRecord::StaleObjectError) { workbench.update!(id: edited.id, version: 0, values: {headline: 'Old tab'}) }
  end
  def test_content_approval_applies_exact_saved_revision_and_payload_changes_invalidate_it
    variant = approved
    assert @campaign.content_review_required?
    assert @campaign.content_approved?
    assert_equal 'ready', @campaign.status
    assert_equal @owner, @campaign.content_approved_by
    assert_equal variant.message, @campaign.message
    assert_equal variant.applied_digest, @campaign.content_digest
    assert_equal variant.id, workbench.approve!(id: variant.id, version: 0).id
    assert_raises(ActiveRecord::RecordInvalid) { variant.update!(message: 'Changed approved text') }
    @campaign.update!(message: 'A revised promise', status: 'ready')
    assert_equal 'draft', @campaign.status
    refute @campaign.content_approved?
    assert_nil @campaign.approved_content_digest
    assert_raises(ArgumentError) { workbench.approve!(id: variant.id, version: 1) }
    assert_raises(ActiveRecord::RecordNotDestroyed) { @campaign.destroy! }
  end
  def test_content_stale_source_brief_disabled_tracking_and_foreign_sites_reject_approval
    rows = variations
    brief(audience: 'Updated audience')
    assert_raises(ArgumentError) { workbench.approve!(id: rows.first.id, version: 0) }
    fresh = variations(key: 'content-generation-2')
    @link.update!(enabled: false)
    assert_raises(ArgumentError) { workbench.approve!(id: fresh.first.id, version: 0) }
    assert_raises(ActiveRecord::RecordNotFound) { workbench(@other).generate!(campaign_id: @campaign.id, request_key: 'foreign-content-1') }
    assert_raises(ActiveRecord::RecordNotFound) { workbench(@designer).update!(id: rows.first.id, version: 0, values: {message: 'No access'}) }
    foreign_campaign = LightekMarketing::Campaign.create!(site: @foreign_site, name: 'Foreign')
    assert_raises(ActiveRecord::RecordNotFound) { workbench.generate!(campaign_id: foreign_campaign.id, request_key: 'foreign-content-2') }
    cached = workbench(@member)
    LightekAgency::SiteMembership.where(user: @member).delete_all
    assert_raises(ActiveRecord::RecordNotFound) { cached.approve!(id: rows.first.id, version: 0) }
  end
  def test_content_delivery_history_blocks_reapplying_new_copy
    variant = variations.first
    LightekMarketing::SocialPost.create!(campaign: @campaign, connection: connection)
    assert_raises(ArgumentError) { workbench.approve!(id: variant.id, version: 0) }
    assert_equal 'draft', @campaign.reload.status
    assert_equal 'draft', variant.reload.status
  end
  def test_content_social_publishing_checks_approval_before_provider_io
    approved
    post = LightekMarketing::SocialPost.create!(campaign: @campaign, connection: connection)
    LightekMarketing::SocialProviders.stub(:publish!, ->(**args) { assert args[:campaign].content_approved?; 'provider-post-1' }) do
      LightekMarketing::SocialDispatch.call!(post: post)
    end
    assert_equal 'published', post.reload.status
    assert_equal 'provider-post-1', post.remote_id
    other_post = LightekMarketing::SocialPost.create!(campaign: @campaign, connection: LightekMarketing::SocialConnection.create!(site: @site, provider: 'facebook', account_label: 'Page 2', credential_key: 'fixture2', publish_endpoint: 'https://graph.facebook.com'))
    @campaign.reload.update!(media_url: 'https://media.test/new.jpg')
    assert_raises(LightekMarketing::SocialDispatch::Unavailable) { LightekMarketing::SocialDispatch.call!(post: other_post) }
    assert_equal 'pending', other_post.reload.status
  end
  def test_content_email_jobs_bind_the_approved_payload_and_fail_closed_after_changes
    @campaign.update!(channel: 'email')
    account = LightekMail::Account.create!(user: @owner, address: 'sender@example.test')
    @campaign.update!(mail_account_id: account.id)
    approved
    contact = LightekMarketing::Contact.create!(site: @site, email: 'subscribed@example.test', subscribed_at: Time.current)
    LightekMarketing::AudienceDispatch.call!(campaign: @campaign)
    delivery = LightekMarketing::Delivery.last
    assert_equal @campaign.content_digest, delivery.content_digest
    assert_equal 'pending', delivery.status
    digest = @campaign.content_digest
    @campaign.update!(message: 'Changed after queueing')
    assert_raises(LightekMarketing::EmailDelivery::Invalid) { LightekMarketing::EmailDelivery.call!(campaign: @campaign, actor: @owner) }
    LightekMarketing::CampaignDeliveryJob.perform_now(delivery.id)
    assert_equal 'failed', delivery.reload.status
    assert_includes delivery.error_message, 'changed'
    before = ActiveJob::Base.queue_adapter.enqueued_jobs.size
    LightekMarketing::ScheduledCampaignJob.perform_now(@campaign.id, digest)
    assert_equal before, ActiveJob::Base.queue_adapter.enqueued_jobs.size
  end
  def test_content_native_review_ui_requires_csrf_saved_revision_and_confirmation
    brief
    csrf = token
    assert_raises(ActionController::InvalidAuthenticityToken) { post generate_dashboard_campaign_content_path(site_id: @site.id, campaign_id: @campaign.id), params: {request_key: 'native-content-1'}, headers: headers }
    post generate_dashboard_campaign_content_path(site_id: @site.id, campaign_id: @campaign.id), params: {request_key: 'native-content-1', tracking_link_id: @link.id}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    variant = LightekMarketing::ContentVariant.first
    post approve_dashboard_campaign_content_variant_path(site_id: @site.id, campaign_id: @campaign.id, id: variant.id), params: {lock_version: 0}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_equal 'draft', variant.reload.status
    post approve_dashboard_campaign_content_variant_path(site_id: @site.id, campaign_id: @campaign.id, id: variant.id), params: {lock_version: 0, confirmed: '1'}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_equal 'approved', variant.reload.status
    get dashboard_campaign_content_path(site_id: @site.id, campaign_id: @campaign.id), headers: headers
    assert_response :success
    assert_select 'h1', text: 'Campaign content & review'
    assert_includes response.body, 'Approve &amp; use this version'
    assert_includes response.body, 'immutable'
    File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'campaign-content.html'), response.body) if ENV['SALES_PREVIEW_DIR']
  end
  def test_content_social_campaign_is_a_focused_studio_production_and_reopen_preserves_edits
    variant = approved
    @campaign.update!(production_format: 'square')
    refute @campaign.content_approved?
    variant = variations(key: 'square-content-1').first
    workbench.approve!(id: variant.id, version: 0)
    scene = ContentTestScene.create!(settings: {})
    allocation = ->(operation, payload) { assert_equal 'project_create', operation; assert_equal 'square', payload['format']; {scene_id: scene.id} }
    Studio::Workers::Workspace.stub(:perform, allocation) do
      brief(audience: 'Changed after approval')
      opened = LightekMarketing::StudioProduction.open!(campaign: @campaign.reload, actor: @owner)
      assert_equal 'Local shops', opened.settings.dig('campaign_production_brief', 'audience')
      assert opened.settings['campaign_content_approved']
      assert_equal @campaign.content_digest, opened.settings['campaign_content_digest']
      assert_includes opened.settings.dig('workspace', 'story', 'scriptDraft'), @campaign.message
      settings = opened.settings.deep_dup
      settings['workspace']['story']['scriptDraft'] = 'Creative edits to preserve'
      settings['timeline'] = {'clips' => ['existing media']}
      opened.update!(settings: settings)
      reopened = LightekMarketing::StudioProduction.open!(campaign: @campaign, actor: @owner)
      assert_equal 'Creative edits to preserve', reopened.settings.dig('workspace', 'story', 'scriptDraft')
      synced = LightekMarketing::StudioProduction.sync_brief!(campaign: @campaign, actor: @owner)
      assert_includes synced.settings.dig('workspace', 'story', 'scriptDraft'), @campaign.message
      assert_equal ['existing media'], synced.settings.dig('timeline', 'clips')
    end
  end
  def test_content_scheduled_send_is_bound_to_the_reviewed_version_even_after_reapproval
    @campaign.update!(channel: 'email')
    account = LightekMail::Account.create!(user: @owner, address: 'sender@example.test')
    @campaign.update!(mail_account_id: account.id)
    approved
    old_digest = @campaign.content_digest
    @campaign.update!(message: 'A different reviewed offer')
    variant = variations(key: 'scheduled-content-2').first
    workbench.update!(id: variant.id, version: 0, values: {message: 'A different reviewed offer'})
    workbench.approve!(id: variant.id, version: 1)
    @campaign.reload
    refute_equal old_digest, @campaign.content_digest
    assert @campaign.content_approved?
    LightekMarketing::Contact.create!(site: @site, email: 'subscriber@example.test', subscribed_at: Time.current)
    LightekMarketing::ScheduledCampaignJob.perform_now(@campaign.id, old_digest)
    assert_equal 0, LightekMarketing::Delivery.count
    assert_raises(ArgumentError) { LightekMarketing::AudienceDispatch.call!(campaign: @campaign, expected_digest: old_digest) }
    LightekMarketing::ScheduledCampaignJob.perform_now(@campaign.id, @campaign.content_digest)
    assert_equal 1, LightekMarketing::Delivery.count
    assert_equal @campaign.content_digest, LightekMarketing::Delivery.last.content_digest
  end
  def test_content_legacy_workflow_and_optimistic_editor_version_are_explicit
    assert @campaign.content_approved?
    @campaign.update!(status: 'ready')
    assert_equal 'ready', @campaign.status
    csrf = token
    patch dashboard_marketing_campaign_path(@campaign, site_id: @site.id), params: {campaign: {headline: 'Old editor', lock_version: @campaign.lock_version - 1}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :redirect
    refute_equal 'Old editor', @campaign.reload.headline
    variant = approved
    assert_raises(ActiveRecord::RecordInvalid) { workbench.update!(id: variations(key: 'long-url-content').first.id, version: 0, values: {cta_url: 'https://example.test/' + 'x' * 400}) }
    @campaign.update!(recipient_email: 'different@example.test', status: 'ready')
    refute @campaign.content_approved?
    assert_equal 'draft', @campaign.status
  end

  def test_content_approved_audience_worker_delivers_exact_copy_once
    @campaign.update!(channel: 'email')
    account = LightekMail::Account.create!(user: @owner, address: 'sender@example.test')
    @campaign.update!(mail_account_id: account.id)
    approved
    LightekMarketing::Contact.create!(site: @site, email: 'subscriber@example.test', subscribed_at: Time.current)
    LightekMarketing::AudienceDispatch.call!(campaign: @campaign)
    delivery = LightekMarketing::Delivery.last
    calls = []
    LightekMail::Submission.stub(:create!, ->(**args) { calls << args; LightekMail::Message.create!(account_id: account.id) }) do
      2.times { LightekMarketing::CampaignDeliveryJob.perform_now(delivery.id) }
    end
    assert_equal 1, calls.size
    assert_equal @campaign.headline, calls.first[:attributes]['subject']
    assert_includes calls.first[:attributes]['text'], @campaign.message
    assert_includes calls.first[:attributes]['text'], @campaign.cta_url
    assert_equal 'queued', delivery.reload.status
    assert delivery.mail_message_id.present?
  end

end
