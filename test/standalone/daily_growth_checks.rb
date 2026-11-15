# Extends the real Growth/CRM host with daily planning and the existing Nevaeh
# command, saved-action worker and scheduled-agent pipeline. The private host
# Gatekeeper/Dispatch integration is a boundary fixture, never live provider IO.
require_relative 'growth_foundation_checks'
%w[20261109090000_create_nevaeh_operating_system 20261109141000_connect_nevaeh_agent_workforce].each { |file| require ROOT.join("db/migrate/#{file}") }
CreateNevaehOperatingSystem.new.migrate(:up)
ConnectNevaehAgentWorkforce.new.migrate(:up)
ActiveRecord::Schema.define do
  create_table(:nevaeh_capabilities) do |t|
    %i[name slug domain intent_name handler queue subject_type gatekeeper_capability].each { |field| t.string field }
    t.boolean :enabled, default: true; t.integer :priority, default: 5; t.json :event_types, default: []
  end
  create_table(:dymond_dispatch_work_items) do |t|
    t.string :subject_type; t.integer :subject_id; t.string :kind; t.string :status, default: 'queued'; t.json :result, default: {}; t.text :error
  end
end
ActiveRecord::Schema.define do
  create_table(:lightek_mail_accounts) { |t| t.references :user; t.string :address }
  add_column :lightek_marketing_campaigns, :mail_account_id, :integer
  add_column :lightek_marketing_campaigns, :recipient_email, :string
end
LightekMarketing::Campaign.reset_column_information
module LightekMail
  class Account < ApplicationRecord
    self.table_name = 'lightek_mail_accounts'
    belongs_to :user
  end
end
module DymondDispatch
  class WorkItem < ApplicationRecord
    self.table_name = 'dymond_dispatch_work_items'
  end
end
class Nevaeh
  def self.handle(**args)
    DymondDispatch::WorkItem.create!(kind: args.fetch(:capability_hint), subject_type: args[:subject].class.name, subject_id: args[:subject].id)
  end
end
module Gatekeeper
  class AuthorizationDenied < StandardError; end
  def self.authorize_capability!(**) = true
end
module LightekPwa
  class Policy
    class Denied < StandardError; end
  end
end
%w[nevaeh_os_action nevaeh_os_agent nevaeh_agent_worker nevaeh_agent_run nevaeh_capability].each { |file| require ROOT.join("app/models/#{file}") }
%w[command agents executor dispatch worker receipts agent_workforce conversation guide].each { |file| require ROOT.join("app/services/nevaeh_os/#{file}") }
require ROOT.join('app/jobs/nevaeh_os/agent_run_job')
require ROOT.join('app/controllers/dashboard/marketing_campaigns_controller')
Dashboard::MarketingCampaignsController.prepend_view_path ROOT.join('app/views')
Dashboard::MarketingCampaignsController.layout false
# The actual campaign controller/form is the destination for the drafted result.
SalesHarness.routes.draw do
  %w[campaign_content growth lifecycle people sales_quotes sales].each { |file| eval(ROOT.join("config/routes/#{file}.rb").read, binding) }
  get '/orders', to: 'dashboard/sales#index', as: :dashboard_commerce_orders
  get '/customers/history', to: 'dashboard/sales#index', as: :history_dashboard_customers
  get '/csrf', to: 'dashboard/settings_home#csrf'
  post '/website-inquiry', to: 'website_template_inquiries#create'
  get '/shop', to: 'commerce#index', as: :commerce_shop
  post '/shop/add', to: 'commerce#add'
  post '/shop/checkout', to: 'commerce#checkout'
  get '/campaigns/:id/edit', to: 'dashboard/marketing_campaigns#edit', as: :edit_dashboard_marketing_campaign
  post '/campaigns/:id/studio', to: 'dashboard/marketing_campaigns#studio', as: :studio_dashboard_marketing_campaign
  patch '/campaigns/:id', to: 'dashboard/marketing_campaigns#update', as: :dashboard_marketing_campaign
  get '/campaigns', to: 'dashboard/marketing_campaigns#index', as: :dashboard_marketing_campaigns
  %w[business_hub website_designs media_studio commerce customers pwa].each do |name|
    get "/workspace/#{name}", to: 'dashboard/sales#index', as: "dashboard_#{name}"
  end
end
SalesCrmChecks.prepend(Module.new do
  def setup
    [NevaehAgentRun, NevaehAgentWorker, NevaehOsAction, NevaehOsAgent, DymondDispatch::WorkItem, NevaehCapability].each(&:delete_all)
    super
  end
end)
class DailyGrowthChecks < GrowthFoundationChecks
  def self.runnable_methods = instance_methods.grep(/^test_daily_/).map(&:to_s)
  def planner(actor = @owner, site = @site) = LightekGrowth::DailyPlanner.new(actor: actor, site: site)
  def brief(**values)
    @growth.save_brief!(values: {offering: 'Managed websites', audience: 'Local shops', customer_problem: 'Disconnected tools', value_proposition: 'One place to run the business', voice: 'Warm and clear', goal: 'Find ten paying clients', goal_on: Date.current + 30}.merge(values), version: LightekGrowth::Brief.find_by(site: @site)&.lock_version)
  end
  def draft_step(plan) = plan.steps.find { |step| step.definition['action'] == 'create_campaign' }
  def visit_once = LightekGrowth::Visit.create!(site: @site, link: @link)
  def refresh(plan, key: SecureRandom.uuid) = planner.prepare!(refresh_from: plan.id, request_key: key)
  def test_daily_preparation_is_idempotent_refresh_is_versioned_and_evidence_immutable
    plan = planner.prepare!
    assert_equal ['brief'], plan.steps.map(&:key)
    assert_equal plan, planner.prepare!
    assert_equal 1, LightekGrowth::Plan.count
    assert_equal false, plan.snapshot['brief_complete']
    brief
    assert_equal false, plan.reload.snapshot['brief_complete']
    key = SecureRandom.uuid
    revised = refresh(plan, key: key)
    assert_equal 2, revised.revision
    assert_equal plan, revised.previous_plan
    assert_equal revised.id, refresh(plan, key: key).id
    assert_equal true, revised.snapshot['brief_complete']
    assert_equal ['distribution'], revised.steps.map(&:key)
    assert_raises(ArgumentError) { refresh(plan) }
    assert_raises(ActiveRecord::RecordInvalid) { plan.update!(snapshot: {}) }
    assert_raises(ActiveRecord::RecordInvalid) { plan.steps.first.update!(definition: {}) }
    assert_equal revised, planner.prepare!
  end
  def test_daily_playbook_prioritizes_existing_customer_work_and_limits_the_plan
    brief(goal_on: Date.current)
    @intake = LightekSales::Intake.new(actor: @owner, site: @site)
    @intake.stage_csv!("name,email\nInterested,interest@example.test\n")
    task_lead = lead
    LightekSales::Tasks.new(actor: @owner, site: @site).create!(kind: 'lead', id: task_lead.id, values: {title: 'Call buyer', owner_id: @member.id, due_at: Time.current - 1.hour})
    order = LightekCommerce::OrderPlacement.call(site: @site, customer_email: 'buyer@example.test', quantities: {offer.id.to_s => 1})
    settle(order)
    issued_quote = issued
    issued_quote.update_columns(expires_on: Date.current + 2)
    plan = planner.prepare!
    assert_equal %w[inquiries delivery follow_up quotes goal_review], plan.steps.map(&:key)
    assert_equal (1..5).to_a, plan.steps.map(&:position)
    assert_equal 1, plan.snapshot.dig('facts', 'paid_undelivered')
    assert_equal 1, plan.snapshot.dig('facts', 'due_tasks')
    assert_equal 1, plan.snapshot.dig('facts', 'review_inquiries')
    assert_equal Date.current.iso8601, plan.snapshot.dig('brief', 'goal_on')
    assert_equal 'growth-daily-v1', plan.playbook_version
    assert_equal 'One place to run the business', plan.snapshot.dig('brief', 'value_proposition')
  end
  def test_daily_sparse_measurements_do_not_invent_conversion_failures
    brief
    plan = planner.prepare!
    assert_equal ['distribution'], plan.steps.map(&:key)
    19.times { visit_once }
    plan = refresh(plan)
    assert_equal ['next_campaign'], plan.steps.map(&:key)
    visit_once
    plan = refresh(plan)
    assert_equal ['landing'], plan.steps.map(&:key)
    assert_includes plan.steps.first.definition['reason'], 'not proof'
    assert_equal 20, plan.steps.first.definition.dig('evidence', 'tracked_visits')
    assert_equal 0, plan.snapshot.dig('facts', 'paid_visits')
  end
  def test_daily_campaign_draft_is_reviewable_idempotent_and_not_published
    brief
    visit_once
    plan = planner.prepare!
    step = draft_step(plan)
    initial_count = LightekMarketing::Campaign.count
    first = planner.draft_campaign!(plan_id: plan.id, step_id: step.id, version: 0)
    repeat = planner.draft_campaign!(plan_id: plan.id, step_id: step.id, version: 0)
    assert_equal first.result, repeat.result
    assert_equal initial_count + 1, LightekMarketing::Campaign.count
    campaign = LightekMarketing::Campaign.find(first.result.fetch('campaign_id'))
    assert_equal 'draft', campaign.status
    assert_equal 'Managed websites', campaign.headline
    assert_includes campaign.message, 'For Local shops'
    assert_includes campaign.message, 'One place to run the business'
    assert_equal @site.id, campaign.site_id
    assert_equal 'campaign_draft', first.resolution_source
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
    assert_equal 0, funnel.stages['Confirmed payment']
    get edit_dashboard_marketing_campaign_path(campaign, site_id: @site.id), headers: headers(@member)
    assert_response :success
    assert_includes response.body, 'Managed websites'
    csrf = token(@member)
    patch dashboard_marketing_campaign_path(campaign, site_id: @site.id), params: {campaign: {headline: 'Reviewed managed website offer', lock_version: (campaign.has_attribute?(:lock_version) ? campaign.lock_version : 0)}}, headers: headers(@member).merge('X-CSRF-Token' => csrf)
    assert_response :redirect
    assert_equal 'Reviewed managed website offer', campaign.reload.headline
    assert_equal 'draft', campaign.status
    assert_raises(ActiveRecord::RecordNotFound) { get edit_dashboard_marketing_campaign_path(campaign, site_id: @site.id), headers: headers(@designer) }
  end
  def test_daily_changed_brief_historical_plan_and_deleted_draft_require_refresh
    brief
    visit_once
    plan = planner.prepare!
    step = draft_step(plan)
    brief(offering: 'Updated offer')
    assert_raises(ArgumentError) { planner.draft_campaign!(plan_id: plan.id, step_id: step.id, version: 0) }
    revised = refresh(plan)
    assert_raises(ArgumentError) { planner.resolve!(plan_id: plan.id, step_id: step.id, version: 0, status: 'completed', note: 'Old tab') }
    new_step = draft_step(revised)
    planner.draft_campaign!(plan_id: revised.id, step_id: new_step.id, version: 0)
    campaign_id = new_step.reload.result.fetch('campaign_id')
    LightekMarketing::Campaign.find(campaign_id).destroy!
    assert_raises(ArgumentError) { planner.draft_campaign!(plan_id: revised.id, step_id: new_step.id, version: 1) }
    travel 1.day do
      tomorrow = planner.prepare!
      assert_equal Date.current, tomorrow.plan_on
      assert_equal 1, tomorrow.revision
      refute revised.current?
      assert_raises(ArgumentError) { planner.resolve!(plan_id: revised.id, step_id: new_step.id, version: 1, status: 'completed', note: 'Yesterday') }
    end
  end
  def test_daily_resolution_requires_evidence_and_keeps_business_outcomes_separate
    plan = planner.prepare!
    step = plan.steps.first
    assert_raises(ArgumentError) { planner.resolve!(plan_id: plan.id, step_id: step.id, version: 0, status: 'completed', note: '') }
    assert_raises(ActiveRecord::StaleObjectError) { planner.resolve!(plan_id: plan.id, step_id: step.id, version: 5, status: 'completed', note: 'Done') }
    result = planner.resolve!(plan_id: plan.id, step_id: step.id, version: 0, status: 'dismissed', note: 'Need to discuss audience with the team')
    assert_equal @owner, result.resolved_by
    assert_equal 'operator', result.resolution_source
    assert_equal 'dismissed', result.status
    assert_equal result, planner.resolve!(plan_id: plan.id, step_id: step.id, version: 0, status: 'dismissed', note: result.resolution_note)
    assert_equal 0, LightekSales::Task.count
    assert_equal 0, LightekCommerce::Order.count
    assert_equal false, plan.snapshot['brief_complete']
  end
  def test_daily_native_http_csrf_history_plan_scope_and_controls
    assert_raises(ActionController::InvalidAuthenticityToken) { post prepare_dashboard_growth_plan_path(site_id: @site.id), headers: headers }
    csrf = token
    post prepare_dashboard_growth_plan_path(site_id: @site.id), headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    plan = LightekGrowth::Plan.last
    get dashboard_growth_path(site_id: @site.id, plan_id: plan.id), headers: headers
    assert_response :success
    assert_select '#daily-growth-plan h2', text: 'Daily growth plan'
    assert_includes response.body, 'Finish your business growth brief'
    assert_includes response.body, 'Why Nevaeh recommended this'
    assert_raises(ActiveRecord::RecordNotFound) { get dashboard_growth_path(site_id: @foreign_site.id, plan_id: plan.id), headers: headers(@other) }
    step = plan.steps.first
    patch resolve_dashboard_growth_step_path(site_id: @site.id, plan_id: plan.id, id: step.id), params: {lock_version: 0, status: 'completed', note: 'Reviewed the offer with the owner'}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_equal 'completed', step.reload.status
    brief
    visit_once
    plan = refresh(plan)
    step = draft_step(plan)
    post draft_dashboard_growth_step_path(site_id: @site.id, plan_id: plan.id, id: step.id), params: {lock_version: 0}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_match '/campaigns/', response.location
    get dashboard_growth_path(site_id: @site.id), headers: headers
    assert_response :success
    assert_includes response.body, 'Draft creation recorded'
    File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'growth-plan.html'), response.body) if ENV['SALES_PREVIEW_DIR']
  end
  def test_daily_permissions_are_rechecked_for_cached_planners_and_step_execution
    plan = planner.prepare!
    step = plan.steps.first
    assert_raises(ActiveRecord::RecordNotFound) { planner(@other).prepare! }
    assert_raises(ActiveRecord::RecordNotFound) { planner(@designer).prepare! }
    cached = planner(@member)
    LightekAgency::SiteMembership.where(user: @member).delete_all
    assert_raises(ActiveRecord::RecordNotFound) { cached.resolve!(plan_id: plan.id, step_id: step.id, version: 0, status: 'completed', note: 'Not allowed') }
    LightekAgency::PackagePolicy.allowed = false
    assert_raises(LightekAgency::PackagePolicy::Denied) { planner.prepare! }
    assert_equal 1, LightekGrowth::Plan.count
  end
  def test_daily_nevaeh_command_worker_receipt_and_replay
    parsed = NevaehOs::Command.parse("/growth #{@site.id}")
    assert_equal({'kind' => 'growth_plan', 'site_id' => @site.id}, parsed)
    assert_equal parsed, NevaehOs::Command.parse("show my growth plan #{@site.id}")
    result = NevaehOs::Conversation.new(actor: @owner).ask(text: "/growth #{@site.id}", request_key: 'growth-conversation-1', mode: 'operate')
    assert_equal 'pending', result['status']
    action = NevaehOsAction.find(result.fetch('action_id'))
    receipt = NevaehOs::Worker.perform('execute', {'action_id' => action.id})
    assert_equal 'prepared', receipt['status']
    assert_equal @site.id, receipt['site_id']
    assert_match '/dashboard/growth', receipt['url']
    assert_equal 'completed', action.reload.status
    assert_equal receipt, NevaehOs::Worker.perform('execute', {'action_id' => action.id})
    assert_equal 1, LightekGrowth::Plan.count
    assert_equal 'growth.plan', NevaehOs::Agents.capability(parsed)
    Rails.stub(:root, ROOT) { assert_includes NevaehOs::Guide.tutorial('growth', actor: @owner)[:body], '/growth SITE_ID' }
    assert_raises(ArgumentError) { NevaehOs::Guide.tutorial('growth', actor: @designer) }
    assert_raises(ArgumentError) { NevaehOs::Executor.authorize_command!(actor: @owner, command: {'kind' => 'growth_plan', 'site_id' => [@site.id]}) }
    agent = NevaehOs::Agents.resolve!('sage', @owner)
    agent.update!(allowed_capabilities: ['studio.*'])
    assert_raises(ArgumentError) { NevaehOs::Executor.authorize_command!(actor: @owner, command: parsed.merge('agent_id' => agent.id)) }
    read_only = NevaehOs::Conversation.new(actor: @owner).ask(text: "/growth #{@site.id}", request_key: 'growth-plan-reflection', mode: 'reflect')
    assert_equal 'planned', read_only['status']
    assert_equal 1, LightekGrowth::Plan.count
  end
  def test_daily_agent_schedule_uses_existing_tick_and_pauses_after_revocation
    agent = NevaehOs::Agents.resolve!('sage', @member)
    agent.update!(allowed_capabilities: ['growth.plan'])
    command = {'kind' => 'agent_task', 'agent_ref' => agent.id.to_s, 'interval_minutes' => 1440, 'command' => {'kind' => 'growth_plan', 'site_id' => @site.id}}
    NevaehOs::Executor.authorize_command!(actor: @member, command: command)
    receipt = NevaehOs::AgentWorkforce.create!(actor: @member, command: command, key: 'daily-growth-schedule')
    worker = NevaehAgentWorker.find(receipt.fetch('agent_worker_id'))
    assert_equal 1440, worker.interval_minutes
    assert_equal 'scheduled', agent.reload.autonomy
    travel 1.day + 1.minute do
      NevaehOs::AgentWorkforce.tick!
      run = worker.runs.last
      assert_equal 'queued', run.status
      NevaehOs::AgentRunJob.perform_now(run.id)
      action = run.reload.nevaeh_os_action
      NevaehOs::Worker.perform('execute', {'action_id' => action.id})
      assert_equal 'completed', action.reload.status
      assert_equal Date.current, LightekGrowth::Plan.last.plan_on
      LightekAgency::SiteMembership.where(user: @member).delete_all
      travel 1.day + 1.minute
      NevaehOs::AgentWorkforce.tick!
      refute worker.reload.enabled?
      assert_equal 1, LightekGrowth::Plan.count
    end
  end
  def test_daily_first_campaign_and_missing_tracking_have_distinct_next_moves
    @link.destroy!
    @campaign.destroy!
    brief
    plan = planner.prepare!
    assert_equal ['first_campaign'], plan.steps.map(&:key)
    step = plan.steps.first
    planner.draft_campaign!(plan_id: plan.id, step_id: step.id, version: 0)
    plan = refresh(plan)
    assert_equal ['tracking'], plan.steps.map(&:key)
    assert_equal 0, plan.snapshot.dig('facts', 'enabled_links')
    assert_equal 1, plan.snapshot.dig('facts', 'campaigns')
  end
  def test_daily_queued_nevaeh_action_cannot_use_revoked_access
    command = NevaehOs::Command.parse("/growth #{@site.id}")
    action = NevaehOs::Dispatch.submit!(actor: @member, command: command, request_key: 'revoked-growth-action')
    LightekAgency::SiteMembership.where(user: @member).delete_all
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::Worker.perform('execute', {'action_id' => action.id}) }
    assert_equal 'failed', action.reload.status
    assert_equal 0, LightekGrowth::Plan.count
    assert action.error.present?
  end

end
