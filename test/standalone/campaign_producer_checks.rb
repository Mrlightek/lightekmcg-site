# Real Studio models/attachments/timeline/FFmpeg; only the package entitlement
# service is a fixture because the host reseller gem is outside this harness.
require_relative 'campaign_studio_checks'
require File.join(ROOT, 'app/services/lightek_sales/access')
require File.join(ROOT, 'app/services/lightek_growth/workspace')
require File.join(ROOT, 'app/models/lightek_growth/brief')
require File.join(ROOT, 'app/services/studio/shots/board')
require File.join(ROOT, 'app/services/studio/providers/ffmpeg_provider')
require File.join(ROOT, 'app/services/lightek_marketing/campaign_producer')
require File.join(ROOT, 'app/services/lightek_marketing/campaign_composition')
require File.join(ROOT, 'app/jobs/campaign_production_job')
require File.join(ROOT, 'app/services/nevaeh_os/command')
ActiveRecord::Schema.define do
  add_column :lightek_marketing_campaigns, :production_format, :string, default: 'portrait'
  add_column :lightek_marketing_campaigns, :lock_version, :integer, default: 0
  add_column :lightek_marketing_campaigns, :content_review_required, :boolean, default: false
  add_column :lightek_marketing_campaigns, :approved_content_digest, :string
  add_column :lightek_marketing_campaigns, :content_approved_by_id, :integer
  add_column :lightek_marketing_campaigns, :content_approved_at, :datetime
  create_table(:lightek_growth_briefs) do |t|
    t.references :site; t.references :updated_by
    t.text :offering, :audience, :customer_problem, :value_proposition, :voice, :goal
    t.date :goal_on; t.integer :lock_version, default: 0; t.timestamps
  end
end
LightekMarketing::Campaign.reset_column_information
module LightekAgency
  class PackagePolicy
    class Denied < StandardError; end
    class << self
      attr_accessor :blocked
      def authorize!(*_)
        raise Denied, 'Marketing disabled' if blocked
      end
    end
  end
end
class CampaignProducerChecks < CampaignStudioChecks
  CampaignStudioChecks.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    [NevaehWorkerReportReview,NevaehWorkerReport,NevaehAgentRun,NevaehAgentWorker,NevaehOsAction,NevaehOsAgent,DymondDispatch::WorkItem].each(&:delete_all)
    super
    LightekAgency::PackagePolicy.blocked = false
    LightekGrowth::Brief.delete_all
    Rails.application.routes.url_helpers.define_singleton_method(:rails_blob_path) { |attachment, **_| "/rails/active_storage/blobs/#{attachment.blob.id}" }
  end
  def produce(values = {}, key: SecureRandom.uuid)
    LightekMarketing::CampaignProducer.start!(actor: @alice, site: @site, values: {'service'=>'Xyzzy service'}.merge(values), request_key: key)
  end
  def operation(receipt) = StudioOperation.find(receipt.fetch('operation_id'))
  def test_producer_parses_the_requested_phrase_and_rejects_bad_inputs
    command = NevaehOs::Command.parse('make me a funny tiktok campaign ad promoting xyzzy service')
    assert_equal 'campaign_produce', command['kind']
    assert_equal 'xyzzy service', command.dig('values','service')
    assert_equal 'funny', command.dig('values','tone')
    assert_equal 'status', NevaehOs::Command.parse('/campaign status 123')['operation']
    assert_equal 9, NevaehOs::Command.parse('/campaign {"site_id":9,"service":"Xyzzy"}')['site_id']
    [{'service'=>'x'*81}, {'cta_url'=>'http://bad.test'}, {'cta_url'=>'https://user:pass@example.com'}, {'tone'=>'unknown'}, {'image_ids'=>['1']}, {'shell'=>'hi'}].each do |values|
      assert_raises(ArgumentError) { produce(values) }
    end
  end
  def test_producer_reuses_request_and_captures_only_matching_facts
    LightekGrowth::Brief.create!(site: @site, updated_by: @alice, offering: 'Different service', value_proposition: 'Unrelated promise')
    key = SecureRandom.uuid
    first = produce({}, key: key)
    assert_equal first['operation_id'], produce({}, key: key)['operation_id']
    assert_nil first.dig('plan','description')
    assert_nil operation(first).studio_scene.settings.dig('campaign_production_brief','audience')
    refute_includes first['plan'].to_json, 'Unrelated promise'
    assert_raises(ArgumentError) { produce({'service'=>'Other'}, key: key) }
    brief = LightekGrowth::Brief.first
    brief.update!(offering: 'Xyzzy service', value_proposition: 'Book a video consultation.', audience: 'Local shops')
    matching = produce
    assert_equal 'Book a video consultation.', matching.dig('plan','description')
    assert_equal brief.id, matching.dig('plan','source','brief_id')
    assert_equal brief.lock_version, matching.dig('plan','source','brief_revision')
    campaign = LightekMarketing::Campaign.find(matching['campaign_id'])
    assert_equal 'draft', campaign.status
    assert campaign.content_review_required?
    refute campaign.content_approved?
  end
  def test_producer_scope_and_revoked_access_are_rechecked_by_worker
    first = produce
    op = operation(first)
    assert_raises(ActiveRecord::RecordNotFound) { LightekMarketing::CampaignProducer.find!(op.id, actor: @bob) }
    LightekAgency::PackagePolicy.blocked = true
    assert_raises(ArgumentError) { CampaignProductionJob.perform_now(op.id) }
    assert_equal 'failed', op.reload.status
    assert_empty op.artifacts
  end
  def test_producer_builds_editable_layers_and_real_mp4_then_retries_snapshot_without_overwriting_edits
    first = produce({'description'=>'Book a video consultation.'})
    op = operation(first)
    CampaignProductionJob.perform_now(op.id)
    assert_equal 'completed', op.reload.status, op.error_message
    scene = op.studio_scene.reload
    timeline = scene.settings.fetch('timeline')
    assert_equal [1080,1920,24.0], timeline.values_at('width','height','duration')
    assert_equal 5, timeline['clips'].size
    assert_equal 5, timeline['titles'].size
    assert_equal 4, scene.settings.dig('shot_board','shots').size
    assert_equal 3, scene.settings.dig('music','tracks').size
    assert_includes scene.settings.dig('workspace','story','scriptDraft'), 'Book a video consultation.'
    assert op.metadata['draft_preview']
    assert_nil scene.settings['editor_kind']
    artifact = op.artifacts.sole
    Dir.mktmpdir('campaign-result-') do |root|
      file = File.join(root,'ad.mp4'); File.binwrite(file, artifact.file.download)
      info, status = Open3.capture2('ffprobe','-v','error','-show_streams','-show_format','-of','json',file)
      assert status.success?
      data = JSON.parse(info)
      assert_in_delta 24, data.dig('format','duration').to_f, 0.1
      video = data['streams'].find { |stream| stream['codec_type']=='video' }
      assert_equal [720,1280], video.values_at('width','height')
      assert data['streams'].any? { |stream| stream['codec_type']=='audio' }
      if ENV['CAMPAIGN_QA_OUTPUT']
        File.binwrite(ENV.fetch('CAMPAIGN_QA_OUTPUT'), artifact.file.download)
      end
    end
    result = LightekMarketing::CampaignProducer.receipt(op, actor: @alice)
    assert_equal 3, result['links'].size
    before = op.artifacts.count
    CampaignProductionJob.perform_now(op.id)
    assert_equal before, op.artifacts.count
    snapshot = op.manifest['timeline'].deep_dup
    settings = scene.settings.deep_dup; settings['workspace']['story']['scriptDraft'] = 'Human revision'
    scene.update!(settings: settings)
    op.update!(status: 'failed')
    LightekMarketing::CampaignProducer.retry!(op.id, actor: @alice)
    Studio::Providers::FfmpegProvider.stub(:new, ->(_) { Object.new.tap { |provider| def provider.call = {} } }) { CampaignProductionJob.perform_now(op.id) }
    assert_equal snapshot, op.reload.manifest['timeline']
    assert_equal 'Human revision', scene.reload.settings.dig('workspace','story','scriptDraft')
  end
  def test_producer_does_not_overwrite_scene_edited_while_waiting
    op = operation(produce)
    op.studio_scene.update!(settings: op.studio_scene.settings.merge('human_edit'=>true))
    assert_raises(ActiveRecord::StaleObjectError) { CampaignProductionJob.perform_now(op.id) }
    assert_equal 'failed', op.reload.status
    assert op.studio_scene.reload.settings['human_edit']
    assert_nil op.manifest['timeline']
  end
  def test_producer_rejects_foreign_image_and_uses_owned_image
    foreign = StudioAsset.create!(owner: @bob, site: @other_site, name: 'Private', kind: 'image', status: 'ready', request_key: SecureRandom.uuid)
    assert_raises(ArgumentError) { produce({'image_ids'=>[foreign.id]}) }
    first = operation(produce)
    LightekMarketing::CampaignComposition.new(first, @alice).build!
    image = StudioAsset.where(owner: @alice, kind: 'image').where.not(id: foreign.id).last
    op = operation(produce({'image_ids'=>[image.id]}))
    LightekMarketing::CampaignComposition.new(op, @alice).build!
    assert_equal image.id, op.reload.manifest['timeline']['clips'].first['asset_id']
  end
end

# The exact natural phrase also travels through the saved-action/Dispatch path;
# no direct conversational shortcut around the executor or production worker.
%w[20261109090000_create_nevaeh_operating_system 20261109141000_connect_nevaeh_agent_workforce].each { |file| require File.join(ROOT,"db/migrate/#{file}") }
CreateNevaehOperatingSystem.new.migrate(:up)
ConnectNevaehAgentWorkforce.new.migrate(:up)
require File.join(ROOT,'db/migrate/20261115235000_add_nevaeh_workforce_goals')
AddNevaehWorkforceGoals.new.migrate(:up)
ActiveRecord::Schema.define do
  create_table(:nevaeh_capabilities) do |t|
    %i[name slug domain intent_name handler queue subject_type gatekeeper_capability].each { |field| t.string field }
    t.boolean :enabled, default: true; t.integer :priority, default: 5; t.json :event_types, default: []
  end
  create_table(:dymond_dispatch_work_items) do |t|
    t.string :subject_type; t.integer :subject_id; t.string :kind; t.string :status, default: 'queued'; t.json :result, default: {}; t.text :error
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
%w[nevaeh_os_action nevaeh_os_agent nevaeh_agent_worker nevaeh_agent_run nevaeh_capability].each { |file| require File.join(ROOT,"app/models/#{file}") }
%w[agents executor dispatch worker receipts page_context page_workers workforce conversation guide].each { |file| require File.join(ROOT,"app/services/nevaeh_os/#{file}") }
%w[20261116010000_create_nevaeh_worker_reports 20261116020000_add_structured_worker_results 20261116030000_reserve_nevaeh_task_uuids].each { |file| require File.join(ROOT,"db/migrate/#{file}") }
CreateNevaehWorkerReports.new.migrate(:up)
AddStructuredWorkerResults.new.migrate(:up)
ReserveNevaehTaskUuids.new.migrate(:up)
%w[nevaeh_worker_report nevaeh_worker_report_review].each { |file| require File.join(ROOT,"app/models/#{file}") }
%w[report_schema report_journal documentation_workers worker_reports agent_workforce].each { |file| require File.join(ROOT,"app/services/nevaeh_os/#{file}") }
require File.join(ROOT,'app/jobs/nevaeh_os/agent_run_job')
CAMPAIGN_REPORT_ROOT=Pathname.new(Dir.mktmpdir('campaign-journal-'))
NevaehOs::ReportJournal.define_singleton_method(:root) { CAMPAIGN_REPORT_ROOT }
at_exit { FileUtils.rm_rf(CAMPAIGN_REPORT_ROOT) }
require 'minitest/mock'
class CampaignProducerChecks
  def test_producer_conversation_uses_dispatch_receipts_and_planning_does_not_write
    Rails.stub(:root,Pathname.new(ROOT)) do
    phrase = 'make me a funny tiktok campaign ad promoting xyzzy service'
    chat = NevaehOs::Conversation.new(actor: @alice, host: @site.host)
    count = LightekMarketing::Campaign.count
    assert_raises(ArgumentError) { chat.ask(text: '/campaign {"site_id":[1],"service":"Xyzzy"}', request_key: SecureRandom.uuid, mode: 'operate') }
    assert_equal 'planned', chat.ask(text: phrase, request_key: SecureRandom.uuid, mode: 'reflect')['status']
    assert_equal count, LightekMarketing::Campaign.count
    result = chat.ask(text: phrase, request_key: SecureRandom.uuid, mode: 'operate')
    action = NevaehOsAction.find(result.fetch('action_id'))
    assert_equal @site.id, action.command.dig('command','site_id')
    assert_equal 'marketing.campaign.produce', NevaehOs::Agents.capability(action.command.fetch('command'))
    assert_equal 'Campaign Producer',result['delegated_to']
    delegation = NevaehOs::Worker.perform('execute', {'action_id'=>action.id})
    run=NevaehAgentRun.find(delegation.fetch('agent_run_id'))
    NevaehOs::AgentWorkforce.execute!(run)
    child=run.reload.nevaeh_os_action
    receipt = NevaehOs::Worker.perform('execute', {'action_id'=>child.id})
    op = operation(receipt)
    assert_equal 'pending', op.status
    assert_equal 'completed', action.reload.status
    assert_equal count+1, LightekMarketing::Campaign.count
    assert_equal delegation, NevaehOs::Worker.perform('execute', {'action_id'=>action.id})
    polled = NevaehOs::Receipts.for(action)
    assert_equal 'dispatched', polled[:status]
    assert_equal op.id, polled.dig(:downstream,:downstream,:id)
    op.update!(status: 'failed', error_message: 'Renderer unavailable')
    assert_equal 'failed', NevaehOs::Receipts.for(action)[:status]
    agent = NevaehOs::Agents.resolve!('muse', @alice)
    agent.update!(allowed_capabilities: ['susu.*'])
    routed=chat.ask(text: phrase, request_key: SecureRandom.uuid, agent: 'muse', mode: 'operate')
    assert_equal 'Campaign Producer',routed['delegated_to']
    assert_equal ['susu.*'],agent.reload.allowed_capabilities
    assert_raises(ArgumentError) { chat.ask(text: '/delegate muse '+phrase, request_key: SecureRandom.uuid, mode: 'operate') }
    end
  end
end
