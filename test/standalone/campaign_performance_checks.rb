# Native comparisons, tracking, business outcomes, immutable reviews, authoring,
# HTTP/CSRF and current Nevaeh UUID/documentation/journal execution.
# Inherits explicit private-engine/auth/provider boundaries from the Sales host.
require_relative 'publication_calendar_checks'
# The private Commerce engine has timestamps; add its omitted fixture column.
ActiveRecord::Base.connection.add_column :lightek_commerce_orders, :created_at, :datetime
LightekCommerce::Order.reset_column_information
require ROOT.join('db/migrate/20261116040000_add_campaign_performance_comparisons')
AddCampaignPerformanceComparisons.new.migrate(:up)
%w[comparison comparison_arm performance_review performance_draft].each { |file| require ROOT.join("app/models/lightek_growth/#{file}") }
%w[measurement workspace recommendations].each { |file| require ROOT.join("app/services/lightek_growth/performance/#{file}") }
require ROOT.join('app/controllers/dashboard/campaign_performance_controller')
Dashboard::CampaignPerformanceController.prepend_view_path ROOT.join('app/views')
Dashboard::CampaignPerformanceController.layout false
SalesCrmChecks.prepend(Module.new do
  def setup
    [LightekGrowth::PerformanceDraft, LightekGrowth::PerformanceReview, LightekGrowth::ComparisonArm, LightekGrowth::Comparison].each(&:delete_all)
    super
  end
end)
class CampaignPerformanceChecks < PublicationCalendarChecks
  def self.runnable_methods = instance_methods.grep(/^test_performance_/).map(&:to_s)
  def setup
    super
    brief
    review
    @challenger = LightekMarketing::Campaign.create!(site: @site, name: 'Clearer action', channel: 'social', cta_url: "https://#{@site.host}/")
    work = LightekMarketing::ContentWorkbench.new(actor: @owner, site: @site)
    variant = work.generate!(campaign_id: @challenger.id, request_key: SecureRandom.uuid).first
    work.update!(id: variant.id, version: 0, values: {headline: 'Run your shop from one workspace'})
    work.approve!(id: variant.id, version: variant.reload.lock_version)
    @challenger.reload
  end
  def performance(actor = @owner, site = @site) = LightekGrowth::Performance::Workspace.new(actor: actor, site: site)
  def inputs
    {'name' => 'Clearer offer test', 'hypothesis' => 'Clearer action may bring more paid inquiries.', 'variable' => 'message', 'starts_on' => (Date.current - 15).iso8601, 'ends_on' => (Date.current - 8).iso8601,
     'control_campaign_id' => @campaign.id.to_s, 'challenger_campaign_id' => @challenger.id.to_s, 'source' => 'instagram', 'medium' => 'social', 'control_path' => '/', 'challenger_path' => '/', 'confirmed' => '1'}
  end
  def comparison(values = inputs, key: SecureRandom.uuid)
    row = performance.create!(values: values, request_key: key)
    # Fixture history: simulate an experiment pinned before its recorded visits.
    row.update_columns(created_at: Date.iso8601(values.fetch('starts_on')).beginning_of_day)
    row
  end
  def measure(row, key: SecureRandom.uuid) = performance.review!(comparison_id: row.id, request_key: key)
  def cohort(row, count: 30, payments: [1, 3])
    row.arms.order(:id).each_with_index.map do |arm, i|
      visits = count.times.map { LightekGrowth::Visit.create!(site: @site, link: arm.link, created_at: (Date.current - 10).noon) }
      payments[i].times do |n|
        LightekCommerce::Order.create!(site: @site, customer_email: 'buyer@example.test', status: 'paid', currency: 'usd', total_cents: 1000, refunded_cents: n.zero? ? 200 : 0,
          growth_visit: visits.first, created_at: 9.days.ago, paid_at: 8.days.ago, fulfilled_at: n.zero? ? 1.day.ago : nil)
      end
      visits
    end
  end
  def test_performance_pins_two_reviewed_versions_and_distinct_immutable_links
    values = inputs; row = comparison(values, key: 'comparison-create-1')
    assert_equal row, comparison(values, key: 'comparison-create-1')
    assert_equal 2, row.arms.count
    assert_equal 3, LightekGrowth::Link.count
    assert_equal @campaign.content_digest, row.arms.find_by!(label: 'control').content_digest
    assert_equal 'Local shops', row.brief_snapshot['audience']
    assert_equal 0, LightekMarketing::SocialPost.count
    assert_raises(ArgumentError) { comparison(values.merge('name' => 'Different'), key: 'comparison-create-1') }
    assert_raises(ActiveRecord::RecordInvalid) { row.update!(hypothesis: 'Rewrite evidence') }
    assert_raises(ActiveRecord::RecordInvalid) { row.arms.first.update!(creative_snapshot: {}) }
    refute @campaign.destroy
  end
  def test_performance_rejects_unreviewed_foreign_and_invalid_placements_atomically
    @challenger.update!(message: 'Unapproved change')
    assert_raises(ArgumentError) { comparison }
    assert_equal 0, LightekGrowth::Comparison.count
    assert_equal 1, LightekGrowth::Link.count
    @challenger.reload.update!(content_review_required: false)
    assert_raises(ArgumentError) { comparison }
    assert_raises(ArgumentError) { performance(@other, @foreign_site).create!(values: inputs, request_key: SecureRandom.uuid) }
  end
  def test_performance_existing_reviewed_cta_link_is_bound_without_inventing_past_creative_attribution
    work = LightekMarketing::ContentWorkbench.new(actor: @owner, site: @site)
    variant = work.generate!(campaign_id: @campaign.id, request_key: SecureRandom.uuid, tracking_link_id: @link.id).first
    work.approve!(id: variant.id, version: 0)
    old_visit = LightekGrowth::Visit.create!(site: @site, link: @link, created_at: 1.day.ago)
    row = performance.create!(values: inputs, request_key: SecureRandom.uuid)
    arm = row.arms.find_by!(label: 'control')
    assert_equal @link.id, arm.link_id
    assert arm.creative_snapshot['placement_link_in_copy']
    assert_equal 2, LightekGrowth::Link.count
    assert_equal 0, measure(row).snapshot['arms'].first.dig('stages', 'Tracked visits')
    assert_raises(ArgumentError) { performance.create!(values: inputs, request_key: SecureRandom.uuid) }
    assert_equal 1, LightekGrowth::Comparison.count
    assert LightekGrowth::Visit.exists?(old_visit.id)
  end
  def test_performance_invalid_link_and_dates_roll_back_all_setup
    assert_raises(ActiveRecord::RecordInvalid) { comparison(inputs.merge('challenger_path' => '//external.test')) }
    assert_equal 0, LightekGrowth::Comparison.count
    assert_equal 1, LightekGrowth::Link.count
    assert_raises(ActiveRecord::RecordInvalid) { comparison(inputs.merge('ends_on' => (Date.current + 120).iso8601)) }
    assert_raises(ArgumentError) { comparison(inputs.merge('confirmed' => '0')) }
    assert_raises(ArgumentError) { comparison(inputs.merge('challenger_campaign_id' => @campaign.id.to_s)) }
  end
  def test_performance_measures_distinct_visit_outcomes_money_refunds_and_publication_separately
    row = comparison; visits = cohort(row)
    # Three paid orders from one challenger visit must still be one converted visit.
    WebsiteTemplateInquiry.create!(site: @site, template_key: 'music-nova-raye', section_key: 'contact', fields: {'name' => 'Interested', 'email' => 'person@example.test', 'msg' => 'Please call'}, growth_visit: visits.first.first)
    slot = LightekMarketing::PublicationSlot.create!(site: @site, campaign: @campaign, connection: connection, scheduled_by: @owner, scheduled_at: 10.days.ago, request_key: SecureRandom.uuid, status: 'published', content_digest: @campaign.content_digest)
    result = measure(row, key: 'performance-measure-1')
    assert_equal result.id, measure(row, key: 'performance-measure-1').id
    control, challenger = result.snapshot.fetch('arms')
    assert_equal 30, control.dig('stages', 'Tracked visits')
    assert_equal 1, control.dig('stages', 'Inquiry')
    assert_equal 1, challenger.dig('stages', 'Confirmed payment')
    assert_equal 3, challenger['money'].first['paid_orders']
    assert_equal 3000, challenger['money'].first['collected_cents']
    assert_equal 200, challenger['money'].first['refunded_cents']
    assert_equal 1, control.dig('publication_states', 'published')
    assert_equal 'unavailable', result.snapshot['provider_engagement']
    assert_equal 'test_single_change', result.snapshot.dig('recommendation', 'key')
    assert_equal true, result.snapshot.dig('recommendation', 'can_draft')
    before = result.snapshot.deep_dup
    slot.update!(status: 'needs_review')
    LightekCommerce::Order.last.update!(refunded_cents: 1000)
    assert_equal before, result.reload.snapshot
    assert_raises(ActiveRecord::RecordInvalid) { result.update!(snapshot: {}) }
    assert_equal 1200, measure(row).snapshot['arms'].last['money'].first['refunded_cents']
  end
  def test_performance_no_denominator_is_unknown_and_late_cohorts_are_excluded
    row = comparison
    arm = row.arms.first
    LightekGrowth::Visit.create!(site: @site, link: arm.link, created_at: 1.day.ago)
    result = measure(row)
    assert_nil result.snapshot['arms'].first['payment_rate']
    assert_equal 0, result.snapshot['arms'].first.dig('stages', 'Tracked visits')
    assert_equal 'collect_evidence', result.snapshot.dig('recommendation', 'key')
    assert_raises(ArgumentError) { performance.followup!(review_id: result.id) }
  end
  def test_performance_short_outcome_window_and_changed_version_block_followup
    row = comparison(inputs.merge('starts_on' => (Date.current - 10).iso8601, 'ends_on' => Date.current.iso8601))
    cohort(row)
    result = measure(row)
    assert_equal 'wait_for_outcomes', result.snapshot.dig('recommendation', 'key')
    @campaign.update!(message: 'A newer message')
    @challenger.update!(status: 'paused')
    result = measure(row)
    assert_equal 'inspect_coverage', result.snapshot.dig('recommendation', 'key')
    refute result.snapshot.dig('recommendation', 'can_draft')
    assert_equal 30, result.snapshot['arms'].first.dig('stages', 'Tracked visits')
  end
  def test_performance_observed_difference_uses_visits_not_paid_order_count
    row = comparison; visits = cohort(row, payments: [1, 1])
    LightekCommerce::Order.create!(site: @site, customer_email: 'buyer2@example.test', status: 'paid', currency: 'usd', total_cents: 500, growth_visit: visits.last.last, paid_at: Time.current)
    result = measure(row)
    assert_equal 'review_observed_difference', result.snapshot.dig('recommendation', 'key')
    assert_equal 'challenger', result.snapshot.dig('recommendation', 'starting_arm')
    assert_includes result.snapshot.dig('recommendation', 'reason'), 'not a winner'
  end
  def test_performance_followup_is_one_unapproved_draft_with_pinned_starting_copy
    row = comparison; cohort(row); result = measure(row)
    @campaign.update!(headline: 'Changed since review')
    receipt = performance.followup!(review_id: result.id)
    assert_equal receipt.id, performance.followup!(review_id: result.id).id
    assert_equal row.arms.find_by!(label: 'control').creative_snapshot['headline'], receipt.campaign.headline
    assert_equal 'draft', receipt.campaign.status
    refute receipt.campaign.content_approved?
    assert_nil receipt.campaign.media_url
    assert_equal "https://#{@site.host}/", receipt.campaign.cta_url
    assert_equal 0, LightekMarketing::SocialPost.count
    assert_equal 1, LightekGrowth::PerformanceDraft.count
    assert_nil receipt.campaign.approved_content_digest
  end
  def test_performance_scope_revocation_and_feature_checks_apply_to_every_service_action
    row = comparison; cached = performance(@member)
    LightekAgency::SiteMembership.where(user: @member).delete_all
    assert_raises(ActiveRecord::RecordNotFound) { cached.review!(comparison_id: row.id, request_key: SecureRandom.uuid) }
    assert_raises(ActiveRecord::RecordNotFound) { performance(@other, @foreign_site).review!(comparison_id: row.id, request_key: SecureRandom.uuid) }
    assert_raises(ActiveRecord::RecordNotFound) { performance(@designer) }
    LightekAgency::PackagePolicy.allowed = false
    assert_raises(LightekAgency::PackagePolicy::Denied) { performance.review!(comparison_id: row.id, request_key: SecureRandom.uuid) }
    assert_equal 0, row.reviews.count
  end
  def test_performance_fresh_reviews_replace_stale_recommendations_without_rewriting_history
    row = comparison; cohort(row)
    old = measure(row)
    newer = measure(row)
    assert_raises(ArgumentError) { performance.followup!(review_id: old.id) }
    row.arms.first.link.update!(enabled: false)
    limited = measure(row)
    assert_equal 'inspect_coverage', limited.snapshot.dig('recommendation', 'key')
    assert_raises(ArgumentError) { performance.followup!(review_id: limited.id) }
    assert newer.snapshot.dig('recommendation', 'can_draft')
    row.arms.first.link.update!(enabled: true)
    latest = measure(row)
    travel 8.days do
      assert_raises(ArgumentError) { performance.followup!(review_id: latest.id) }
      assert_equal 1, LightekGrowth::Performance::Recommendations.call(@site)['performance_review_due']
    end
  end
  def test_performance_native_setup_uses_scoped_permitted_inputs
    post dashboard_campaign_performance_path(site_id: @site.id), params: {request_key: 'comparison-http-1', comparison: inputs.merge('site_id' => @foreign_site.id, 'created_by_id' => @other.id)}, headers: headers.merge('X-CSRF-Token' => token)
    assert_response :see_other
    row = LightekGrowth::Comparison.last
    assert_equal @site.id, row.site_id
    assert_equal @owner.id, row.created_by_id
    assert_equal 2, row.arms.count
    assert_nil row.brief_snapshot.dig('request_values', 'created_by_id')
  end
  def test_performance_nevaeh_delegation_rereads_growth_page_and_returns_journal_reference
    row = comparison; cohort(row)
    parsed = NevaehOs::Command.parse("/growth review #{@site.id} #{row.id}")
    assert_equal 'growth_review', parsed['kind']
    assert_equal 'growth.review', NevaehOs::Agents.capability(parsed)
    agent = NevaehOs::Agents.resolve!('sage', @owner)
    agent.update!(allowed_capabilities: ['growth.review'])
    delegated = NevaehOs::AgentWorkforce.create!(actor: @owner, command: {'agent_ref' => agent.id.to_s, 'command' => parsed}, key: 'performance-worker-1')
    run = NevaehAgentRun.find(delegated.fetch('agent_run_id'))
    NevaehOs::AgentWorkforce.execute!(run)
    assert_equal 'docs/nevaeh/tutorials/growth.md', run.reload.snapshot.dig('documentation_read', 'path')
    action = run.nevaeh_os_action
    receipt = NevaehOs::Worker.perform('execute', {'action_id' => action.id})
    assert_equal 'reviewed', receipt['status']
    assert_equal row.id, receipt['comparison_id']
    assert_equal receipt, NevaehOs::Worker.perform('execute', {'action_id' => action.id})
    report = NevaehOs::WorkerReports.capture!(run)
    assert_equal 'completed', report.status
    assert_equal run.task_uuid, report.structured_result['task_id']
    dependency = NevaehOs::WorkerReports.dependency_for!(actor: @owner, run: run)
    assert_match(/\Ajournal:/, dependency['report_ref'])
    resolved = NevaehOs::WorkerReports.resolve!(actor: @owner, dependency: dependency)
    assert_equal action.id, resolved['id']
    assert_equal 1, row.reviews.count
    LightekGrowth::PerformanceReview.where(id: receipt['review_id']).delete_all
    assert_equal 'evidence_unavailable', NevaehOs::Receipts.for(action.reload)[:status]
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor: @owner, dependency: dependency) }
    agent.update!(allowed_capabilities: ['growth.plan'])
    assert_raises(ArgumentError) { NevaehOs::Executor.authorize_command!(actor: @owner, command: parsed.merge('agent_id' => agent.id)) }
  end
  def test_performance_daily_plan_links_to_fresh_measured_review_and_native_http_enforces_csrf
    row = comparison; cohort(row)
    facts = LightekGrowth::Performance::Recommendations.call(@site)
    assert_equal 1, facts['performance_review_due']
    plan = planner.prepare!
    assert plan.steps.any? { |step| step.key == 'performance' && step.definition['destination'] == 'performance' }
    path = review_dashboard_campaign_performance_path(row, site_id: @site.id)
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post path, params: {request_key: 'performance-http-1'}, headers: headers.except('X-CSRF-Token')
    end
    assert_equal 0, row.reviews.count
    post path, params: {request_key: 'performance-http-1'}, headers: headers.merge('X-CSRF-Token' => token)
    assert_response :see_other
    result = row.reviews.last
    assert_equal 0, LightekGrowth::Performance::Recommendations.call(@site)['performance_review_due']
    get dashboard_campaign_performance_path(site_id: @site.id, comparison_id: row.id, review_id: result.id), headers: headers
    assert_response :success
    assert_select 'h1', text: 'Campaign performance'
    assert_includes response.body, 'Observed results'
    assert_includes response.body, 'Prepare editable follow-up'
    assert_includes response.body, 'unknown'
    if ENV['SALES_PREVIEW_DIR']
      FileUtils.mkdir_p(ENV['SALES_PREVIEW_DIR'])
      File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'performance.html'), response.body)
    end
    post draft_dashboard_campaign_performance_path(result, site_id: @site.id), headers: headers.merge('X-CSRF-Token' => token)
    assert_equal 0, LightekGrowth::PerformanceDraft.count
    post draft_dashboard_campaign_performance_path(result, site_id: @site.id), params: {confirmed: '1'}, headers: headers.merge('X-CSRF-Token' => token)
    assert_equal 1, LightekGrowth::PerformanceDraft.count
    assert_raises(ActiveRecord::RecordNotFound) do
      get dashboard_campaign_performance_path(site_id: @foreign_site.id, comparison_id: row.id), headers: headers(@other)
    end
  end
end
