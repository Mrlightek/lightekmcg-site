# Actual Growth/CRM/content services, database, Dashboard and Nevaeh dispatch.
# The existing host authentication and external providers remain boundary fixtures.
ENV['DATABASE_URL'] = 'sqlite3::memory:'
require 'active_storage/engine'
require_relative 'campaign_content_checks'
ActiveRecord::Schema.define do
  add_column :dymond_site_pages, :title, :string
  add_column :dymond_site_pages, :slug, :string
  add_column :dymond_site_pages, :position, :integer
  add_column :dymond_site_sections, :position, :integer
  add_column :dymond_site_sections, :kind, :string
  create_table(:active_storage_blobs) { |t| t.string :key, null: false; t.string :filename, null: false; t.string :content_type; t.text :metadata; t.string :service_name, null: false; t.bigint :byte_size, null: false; t.string :checksum; t.datetime :created_at, null: false }
  create_table(:active_storage_attachments) { |t| t.string :name, null: false; t.string :record_type, null: false; t.bigint :record_id, null: false; t.bigint :blob_id, null: false; t.datetime :created_at, null: false }
end
DymondSite::Page.reset_column_information
DymondSite::Section.reset_column_information
FEATURE_TEST_STORAGE = Dir.mktmpdir('feature-video-storage-')
SalesHarness.config.active_storage.service = 'test'
SalesHarness.config.active_storage.service_configurations = {'test'=>{'service'=>'Disk','root'=>FEATURE_TEST_STORAGE}}
at_exit { FileUtils.rm_rf(FEATURE_TEST_STORAGE) }
require ROOT.join('db/migrate/20261116140000_add_marketing_copilot')
AddMarketingCopilot.new.migrate(:up)
%w[marketing_kit marketing_check_in feature_showcase feature_clip marketing_execution].each { |file| require ROOT.join("app/models/lightek_growth/#{file}") }
%w[marketing_playbook marketing_copilot feature_catalog feature_video showcase_builder marketing_execution_plan].each { |file| require ROOT.join("app/services/lightek_growth/#{file}") }
%w[nevaeh_goal nevaeh_goal_step].each { |file| require ROOT.join("app/models/#{file}") }
require ROOT.join('app/services/nevaeh_os/goals')
require ROOT.join('app/services/nevaeh_os/website_pages')
require ROOT.join('app/services/nevaeh_intelligences/structured_actions')
require ROOT.join('app/services/studio/media_process')
require ROOT.join('app/services/studio/native_blender/runtime')
require ROOT.join('app/jobs/feature_showcase_job')
require ROOT.join('app/jobs/nevaeh_os/goal_tick_job')
require ROOT.join('app/controllers/feature_showcase_videos_controller')
require ROOT.join('app/services/lightek_design/catalog')
SalesHarness.routes.send(:eval_block, proc do
  storage_routes = File.read(ActiveStorage::Engine.root.join('config/routes.rb'))
  storage_routes = storage_routes.sub(/.*?Rails\.application\.routes\.draw do/m, '').sub(/end if ActiveStorage\.draw_routes\s*\z/, '')
  instance_eval(storage_routes, 'active_storage_routes.rb')
  get '/dashboard/nevaeh', to: 'dashboard/marketing_copilot#index', as: :dashboard_nevaeh_os
end)
require ROOT.join('app/controllers/dashboard/marketing_copilot_controller')
Dashboard::MarketingCopilotController.prepend_view_path ROOT.join('app/views')
Dashboard::MarketingCopilotController.layout false
SalesCrmChecks.prepend(Module.new do
  def setup
    LightekGrowth::MarketingExecution.delete_all
    LightekGrowth::FeatureClip.delete_all
    LightekGrowth::FeatureShowcase.delete_all
    NevaehGoalStep.delete_all
    NevaehGoal.delete_all
    LightekGrowth::MarketingCheckIn.delete_all
    LightekGrowth::MarketingKit.delete_all
    super
  end
end)
class MarketingCopilotChecks < CampaignContentChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def copilot(actor = @owner, site = @site) = LightekGrowth::MarketingCopilot.new(actor: actor, site: site)
  def kit(values = {}, key: SecureRandom.uuid) = copilot.prepare!(values: values.stringify_keys, request_key: key)
  def setup
    super
    brief
  end
  def test_prepares_three_persisted_variations_tracking_frozen_evidence_and_bounded_days
    lead(name: 'Jordan', next_step: 'Discuss the website scope', follow_up_on: Date.current)
    saved = kit({source: 'linkedin', minutes_per_day: 15, destination_path: '/contact', cta_label: 'Book a conversation'})
    assert_equal 'draft', saved.campaign.status
    assert_equal %w[benefit offer problem], saved.campaign.content_variants.map(&:angle).sort
    assert_equal 7, saved.snapshot['calendar'].size
    saved.snapshot['calendar'].each { |day| assert_operator day['steps'].sum { |step| step['minutes'] }, :<=, 15 }
    assert_equal 1, saved.snapshot['follow_ups'].size
    link = LightekGrowth::Link.find(saved.snapshot['link_id'])
    assert_equal '/contact', link.destination_path
    saved.campaign.content_variants.each do |variant|
      assert_includes variant.cta_url, "/g/#{link.token}"
      assert_equal 'marketing-kit-copy-v1', variant.source_snapshot['writer_version']
    end
    assert_includes saved.campaign.content_variants.find_by!(angle: 'offer').message, 'Looking for Managed websites?'
    assert_equal LightekGrowth::Brief.find_by!(site: @site).lock_version, saved.snapshot['brief_revision']
    assert_equal 'completed', copilot.receipt(saved)['status']
    assert_empty LightekMarketing::Delivery.all
    assert_empty LightekMarketing::SocialPost.all
    assert_raises(ActiveRecord::RecordInvalid) { saved.update!(snapshot: {}) }
  end
  def test_request_retries_are_idempotent_and_different_inputs_or_actor_block
    saved = kit(key: 'marketing-retry-001')
    counts = [LightekMarketing::Campaign.count, LightekGrowth::Link.count, LightekMarketing::ContentVariant.count, LightekGrowth::Plan.count]
    assert_equal saved.id, kit(key: 'marketing-retry-001').id
    assert_equal counts, [LightekMarketing::Campaign.count, LightekGrowth::Link.count, LightekMarketing::ContentVariant.count, LightekGrowth::Plan.count]
    assert_raises(ArgumentError) { kit({minutes_per_day: 60}, key: 'marketing-retry-001') }
    assert_raises(ArgumentError) { copilot(@member).prepare!(values: {}, request_key: 'marketing-retry-001') }
    @growth.save_brief!(values: {offering: 'A reviewed new offer'}, version: LightekGrowth::Brief.find_by!(site: @site).lock_version)
    assert_equal saved.id, kit(key: 'marketing-retry-001').id
    refute copilot.current?(saved)
    fresh = kit
    assert_equal 'A reviewed new offer', fresh.snapshot.dig('brief', 'offering')
    assert_operator fresh.snapshot['plan_revision'], :>, saved.snapshot['plan_revision']
  end
  def test_combined_daily_cap_and_invalid_destinations_fail_without_side_effects
    [15, 30, 60].each do |minutes|
      LightekGrowth::MarketingPlaybook.calendar(minutes).each { |day| assert_operator day['steps'].sum { |step| step['minutes'] }, :<=, minutes }
    end
    count = LightekMarketing::Campaign.count
    [{minutes_per_day: 90}, {source: 'invented'}, {destination_path: '//evil.test'}, {destination_path: '/../secret'}, {destination_path: '/x?secret=1'}, {cta_label: ''}, {publish_now: true}].each do |values|
      assert_raises(ArgumentError) { kit(values) }
    end
    over_cap = LightekGrowth::MarketingPlaybook.calendar(30)
    over_cap.first['steps'].first['minutes'] = 99
    LightekGrowth::MarketingPlaybook.stub(:calendar, over_cap) { assert_raises(ArgumentError) { kit } }
    assert_equal count, LightekMarketing::Campaign.count
    assert_empty LightekGrowth::MarketingKit.all
    assert_empty LightekGrowth::Plan.all
  end
  def test_missing_brief_and_generation_failure_roll_back_the_entire_kit
    LightekGrowth::Brief.find_by!(site: @site).update!(audience: '')
    assert_raises(ArgumentError) { kit }
    brief
    before = [LightekMarketing::Campaign.count, LightekGrowth::Link.count, LightekGrowth::Plan.count]
    NevaehIntelligences::WritingEngine.stub(:generate, ->(**) { raise ArgumentError, 'writer unavailable' }) { assert_raises(ArgumentError) { kit } }
    assert_equal before, [LightekMarketing::Campaign.count, LightekGrowth::Link.count, LightekGrowth::Plan.count]
    assert_empty LightekGrowth::MarketingKit.all
  end
  def test_follow_up_queue_is_grounded_bounded_and_task_creation_does_not_contact_or_duplicate
    target = lead(name: 'Jordan', status: 'new', next_step: 'Discuss actual scope', follow_up_on: Date.current)
    lead(name: 'Future', email: 'future@example.test', follow_up_on: Date.current + 3)
    lead(name: 'Closed', email: 'closed@example.test', status: 'disqualified')
    saved = kit({minutes_per_day: 30})
    assert_equal [target.id], saved.snapshot['follow_ups'].map { |row| row['lead_id'] }
    assert_includes saved.snapshot['follow_ups'].first['next_step_draft'], 'Discuss actual scope'
    refute_includes saved.snapshot['follow_ups'].first['next_step_draft'], 'our conversation'
    task = copilot.follow_up_task!(id: saved.id, lead_id: target.id)
    assert_equal target, task.record
    assert_equal 'open', task.status
    assert_equal @owner, task.owner
    assert_equal task.id, copilot.follow_up_task!(id: saved.id, lead_id: target.id).id
    second = kit
    assert_equal task.id, copilot.follow_up_task!(id: second.id, lead_id: target.id).id
    assert_equal 1, LightekSales::Task.where(record: target).count
    assert_equal 'new', target.reload.status
    target.update!(next_step: 'Changed next step')
    assert_raises(ArgumentError) { copilot.follow_up_task!(id: second.id, lead_id: target.id) }
  end
  def test_access_revocation_foreign_ids_stale_brief_and_expiry_block_follow_up
    target = lead(follow_up_on: Date.current)
    saved = kit
    assert_raises(ActiveRecord::RecordNotFound) { copilot(@other) }
    assert_raises(ActiveRecord::RecordNotFound) { copilot(@designer) }
    assert_raises(ArgumentError) { copilot.follow_up_task!(id: saved.id, lead_id: 999999) }
    travel_to(8.days.from_now) { assert_raises(ArgumentError) { copilot.follow_up_task!(id: saved.id, lead_id: target.id) } }
    @growth.save_brief!(values: {goal: 'A revised goal'}, version: saved.snapshot['brief_revision'])
    assert_raises(ArgumentError) { copilot.follow_up_task!(id: saved.id, lead_id: target.id) }
    LightekAgency::SiteMembership.where(site: @site, user: @member).delete_all
    assert_raises(ActiveRecord::RecordNotFound) { copilot(@member) }
    service = copilot
    LightekAgency::PackagePolicy.allowed = false
    assert_raises(LightekAgency::PackagePolicy::Denied) { service.prepare!(values: {}, request_key: 'revoked-marketing-001') }
  end
  def test_check_ins_are_append_only_idempotent_and_not_payment_or_publication_evidence
    saved = kit
    row = copilot.check_in!(id: saved.id, day_index: 0, status: 'completed', note: 'Reviewed the draft; no post yet.')
    assert_equal row.id, copilot.check_in!(id: saved.id, day_index: 0, status: 'completed', note: row.note).id
    assert_raises(ArgumentError) { copilot.check_in!(id: saved.id, day_index: 0, status: 'skipped', note: 'Changed history') }
    assert_raises(ArgumentError) { copilot.check_in!(id: saved.id, day_index: 1, status: 'completed', note: 'Too early') }
    assert_raises(ActiveRecord::RecordInvalid) { row.update!(note: 'Overwrite') }
    assert_empty LightekMarketing::SocialPost.all
  end
  def test_dashboard_http_renders_actual_kit_controls_and_rejects_unscoped_and_forged_requests
    saved = kit
    get dashboard_marketing_copilot_path(site_id: @site.id, kit_id: saved.id), headers: headers
    assert_response :success
    assert_includes response.body, 'Know your next move.'
    assert_includes response.body, 'Three angles, one reviewed offer.'
    assert_includes response.body, 'Marketing kit tracking URL'
    assert_includes response.body, 'Save check-in'
    preview = ENV['MARKETING_PREVIEW_PATH']
    if preview
      FileUtils.mkdir_p(File.dirname(preview))
      File.write(preview, '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' + response.body)
    end
    assert_raises(ActionController::InvalidAuthenticityToken) { post prepare_dashboard_marketing_kit_path(site_id: @site.id), params: {request_key: SecureRandom.uuid, kit: {minutes_per_day: 30}}, headers: headers }
    assert_equal 1, LightekGrowth::MarketingKit.count
    post prepare_dashboard_marketing_kit_path(site_id: @site.id), params: {authenticity_token: token, request_key: SecureRandom.uuid, kit: {minutes_per_day: 15}}, headers: headers
    assert_response :see_other
    assert_equal 2, LightekGrowth::MarketingKit.count
    assert_raises(ActiveRecord::RecordNotFound) { get dashboard_marketing_copilot_path(site_id: @site.id, kit_id: saved.id), headers: headers(@other) }
  end
  def test_nevaeh_plain_request_delegates_through_dispatch_and_persists_a_resolvable_worker_report
    NevaehOs::Workforce.install!(@owner)
    reply = NevaehOs::Conversation.new(actor: @owner).ask(text: "prepare my marketing kit for site #{@site.id}", request_key: 'marketing-loop-001', mode: 'operate')
    outer = NevaehOsAction.find(reply.fetch('action_id'))
    assert_equal 'agent_task', outer.command['kind']
    assert_equal 'growth.marketing_kit', NevaehOs::Agents.capability(outer.command['command'])
    NevaehOs::Worker.perform('execute', {'action_id'=>outer.id})
    run = NevaehAgentRun.find(outer.reload.result.fetch('agent_run_id'))
    NevaehOs::AgentWorkforce.execute!(run)
    NevaehOs::Worker.perform('execute', {'action_id'=>run.reload.nevaeh_os_action_id})
    NevaehOs::WorkerReports.capture!(run)
    reference = NevaehOs::WorkerReports.dependency_for!(actor: @owner, run: run)
    receipt = NevaehOs::WorkerReports.resolve!(actor: @owner, dependency: reference)
    assert_equal 'accepted', reference['status']
    assert_equal LightekGrowth::MarketingKit.sole.id, receipt.dig('result', 'kit_id')
    assert_match(/\Ajournal:/, reference['report_ref'])
  end
  def execute_goal_run(run)
    NevaehOs::AgentWorkforce.execute!(run)
    NevaehOs::Worker.perform('execute', {'action_id'=>run.reload.nevaeh_os_action_id})
  end
  def test_execution_builds_real_cms_page_and_mp4s_then_consumes_its_journal_for_follow_up
    target = lead(name: 'Jordan', follow_up_on: Date.current)
    saved = kit
    planner = LightekGrowth::MarketingExecutionPlan.new(actor: @owner, site: @site)
    goal = planner.start!(kit_id: saved.id)
    assert_equal goal.id, planner.start!(kit_id: saved.id).id
    assert_equal 2, goal.steps.count
    NevaehOs::Goals.tick!(goal)
    first = goal.steps.order(:position).first.reload
    execute_goal_run(first.nevaeh_agent_run)
    showcase = LightekGrowth::FeatureShowcase.sole
    refute showcase.page.published?
    assert_equal 'lightek_feature_showcase', showcase.page.sections.sole.kind
    assert_equal 'pending', showcase.status
    NevaehOs::Goals.tick!(goal)
    assert_equal 'running', first.reload.status
    assert_empty LightekSales::Task.where(record: target)
    NevaehOs::WorkerReports.capture!(first.nevaeh_agent_run)
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.dependency_for!(actor: @owner, run: first.nevaeh_agent_run) }
    FeatureShowcaseJob.perform_now(showcase.id)
    assert_equal 'completed', showcase.reload.status
    assert_equal 6, showcase.clips.count
    assert showcase.clips.all?(&:ready?)
    assert showcase.clips.all? { |clip| clip.file.download.start_with?("\x00\x00".b) }
    FileUtils.mkdir_p(ROOT.join('tmp'))
    File.binwrite(ROOT.join('tmp/feature-showcase-sample.mp4'), showcase.clips.first.file.download)
    NevaehOs::Goals.tick!(goal)
    assert_equal 'completed', first.reload.status
    NevaehOs::Goals.tick!(goal)
    second = goal.steps.order(:position).last.reload
    dependency = second.nevaeh_agent_run.snapshot.fetch('report_dependencies').sole
    assert_equal first.nevaeh_agent_run.task_uuid, dependency['task_id']
    assert_equal 'accepted', dependency['status']
    execute_goal_run(second.nevaeh_agent_run)
    NevaehOs::Goals.tick!(goal)
    assert_equal 'completed', goal.reload.status
    assert_equal 1, LightekSales::Task.where(record: target).count
    builder = LightekGrowth::ShowcaseBuilder.new(actor: @owner, site: @site)
    before = builder.receipt(showcase)
    get preview_dashboard_feature_video_path(showcase, position: 0, site_id: @site.id), headers: headers
    assert_response :success
    assert_equal 'video/mp4', response.media_type
    assert_raises(ActiveRecord::RecordNotFound) { get preview_dashboard_feature_video_path(showcase, position: 0, site_id: @site.id), headers: headers(@other) }
    host! @site.host
    assert_raises(ActiveRecord::RecordNotFound) { get feature_showcase_video_path(token: showcase.token, position: 0) }
    stale_source = LightekGrowth::FeatureCatalog.snapshot.merge('sha256'=>'0'*64)
    LightekGrowth::FeatureCatalog.stub(:snapshot, stale_source) { assert_raises(ArgumentError) { builder.approve!(id: showcase.id) } }
    builder.approve!(id: showcase.id)
    assert_raises(ActiveRecord::RecordNotFound) { get feature_showcase_video_path(token: showcase.token, position: 0) }
    showcase.page.update!(published: true)
    get feature_showcase_video_path(token: showcase.token, position: 0)
    assert_response :success
    assert_equal 'video/mp4', response.media_type
    assert response.body.start_with?("\x00\x00".b)
    host! 'wrong.test'
    assert_raises(ActiveRecord::RecordNotFound) { get feature_showcase_video_path(token: showcase.token, position: 0) }
    assert_equal before, builder.receipt(showcase.reload)
    assert NevaehOs::WorkerReports.resolve!(actor: @owner, dependency: dependency)
    host! 'sales.test'
    get dashboard_marketing_copilot_path(site_id: @site.id, kit_id: saved.id), headers: headers
    assert_response :success
    assert_includes response.body, 'Goal #'
    assert_includes response.body, 'private overview'
    # Render the actual public CMS section for the browser acceptance fixture.
    view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([ROOT.join('app/views')]), {}, nil)
    view.extend(SalesHarness.routes.url_helpers)
    view.define_singleton_method(:url_options) { {} }
    view.instance_variable_set(:@site, @site)
    html = view.render(partial: 'dymond_site/themes/default/sections/lightek_feature_showcase', locals: {section: showcase.page.sections.sole})
    assert_equal 6, html.scan('<video ').size
    FileUtils.mkdir_p(ROOT.join('tmp'))
    File.write(ROOT.join('tmp/feature-showcase-preview.html'), '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'+html)
    # The manager must reject missing durable media, not trust its prior report.
    missing = showcase.clips.first.file.blob
    missing.service.delete(missing.key)
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor: @owner, dependency: dependency) }
  end
  def test_render_failure_blocks_execution_before_follow_up_and_pause_is_not_completion
    target = lead(follow_up_on: Date.current)
    saved = kit
    planner = LightekGrowth::MarketingExecutionPlan.new(actor: @owner, site: @site)
    goal = planner.start!(kit_id: saved.id)
    action = NevaehOsAction.create!(user: @owner, request_key: 'paused-marketing-execution', status: 'completed', command: {'kind'=>'marketing_execute','site_id'=>@site.id,'kit_id'=>saved.id}, result: planner.receipt(goal))
    NevaehOs::Goals.control!(goal: goal, actor: @owner, operation: 'pause')
    assert_equal 'dispatched', NevaehOs::Receipts.for(action)[:status]
    NevaehOs::Goals.control!(goal: goal, actor: @owner, operation: 'resume')
    NevaehOs::Goals.tick!(goal)
    execute_goal_run(goal.steps.first.nevaeh_agent_run)
    showcase = LightekGrowth::FeatureShowcase.sole
    LightekGrowth::FeatureVideo.stub(:render!, ->(**) { raise ArgumentError, 'missing media binary' }) { assert_raises(ArgumentError) { FeatureShowcaseJob.perform_now(showcase.id) } }
    assert_equal 'failed', showcase.reload.status
    NevaehOs::Goals.tick!(goal)
    assert_equal 'blocked', goal.reload.status
    assert_empty LightekSales::Task.where(record: target)
    assert_equal 'failed', NevaehOs::Receipts.for(action)[:status]
  end
  def test_production_video_command_reuses_the_existing_isolated_media_container
    captured = nil
    Rails.stub(:env, ActiveSupport::StringInquirer.new('production')) do
      Studio::MediaProcess.stub(:cpu_limit, '1') do
        Studio::MediaProcess.stub(:run!, ->(command, **) { captured = command; '{}' }) do
          LightekGrowth::FeatureVideo.run!(['ffprobe','-v','error','/tmp/feature-test/feature.mp4'], directory: '/tmp/feature-test', timeout: 15)
        end
      end
    end
    assert_equal 'docker', captured.first
    assert_includes captured, '--read-only'
    assert_includes captured, 'none'
    assert_includes captured, '/tmp/feature-test:/work:rw'
    assert_includes captured, Studio::NativeBlender::Runtime.image(:media)
    assert_equal '/work/feature.mp4', captured.last
  end
end
