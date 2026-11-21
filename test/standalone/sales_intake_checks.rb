# Real intake/task migrations, source parser, model callbacks, jobs, services,
# controller HTTP and native views; engine auth/package accounts are fixtures.
require_relative 'sales_crm_checks'
class SalesIntakeChecks < SalesCrmChecks
  def self.runnable_methods = super.grep(/test_intake_/)
  def setup
    super
    @intake = LightekSales::Intake.new(actor: @owner, site: @site)
  end
  def publish_form(site = @site)
    page = DymondSite::Page.create!(site: site, published: true)
    page.sections.create!(data: {'template_key' => 'music-nova-raye', 'section_key' => 'contact'})
    page
  end
  def rule(**values)
    publish_form unless @site.pages.exists?
    @intake.save_rule!({'template_key' => 'music-nova-raye', 'section_key' => 'contact', 'source' => 'website',
      'mapping' => {'name' => 'name', 'email' => 'email', 'message' => 'msg'}, 'enabled' => true}.merge(values.stringify_keys))
  end
  def inquiry(site = @site, **values)
    WebsiteTemplateInquiry.create!(site: site, template_key: 'music-nova-raye', section_key: 'contact', fields: {'name' => 'Jamie Prospect', 'email' => 'jamie@example.test', 'msg' => 'Need managed streaming'}.merge(values.stringify_keys))
  end
  def stage(name: 'Jamie Prospect', email: 'jamie@example.test', source: 'event')
    @intake.stage_csv!("name,email,company,message,source\n#{name},#{email},North Studio,Please call,#{source}\n").first
  end
  def task(record = lead, **values)
    LightekSales::Tasks.new(actor: @owner, site: @site).create!(kind: 'lead', id: record.id,
      values: {title: 'Confirm budget', owner_id: @member.id, due_at: Time.current - 1.hour}.merge(values))
  end
  def test_intake_csv_is_reviewed_bounded_and_replay_safe
    first = stage
    assert_equal 'awaiting_review', first.status
    assert_equal 0, LightekSales::Lead.count
    assert_equal first.id, stage.id
    assert_equal 1, LightekSales::IntakeEntry.count
    assert_equal 'event', first.source
    assert_raises(ArgumentError) { @intake.stage_csv!("email\na@example.test\n") }
    assert_raises(ArgumentError) { @intake.stage_csv!("name,email,email\nA,a@example.test,b@example.test\n") }
    assert_raises(ArgumentError) { @intake.stage_csv!("name,email\n\"broken") }
    assert_raises(ArgumentError) { @intake.stage_csv!("name,email\nA,\0a@example.test") }
    assert_raises(ArgumentError) { @intake.stage_csv!("name,email\n" + "Name,a@example.test\n" * 101) }
    assert_raises(ArgumentError) { @intake.stage_csv!("x" * 512001) }
    assert_raises(ArgumentError) { @intake.stage_csv!("name,email\nA,a@example.test\nB,b@example.test,extra\n") }
    assert_equal 1, LightekSales::IntakeEntry.count
  end
  def test_intake_acceptance_routes_lead_preserves_original_and_creates_one_task
    @workspace.save!('routing_rule', {source: 'event', owner_id: @member.id})
    contact = LightekMarketing::Contact.create!(site: @site, email: 'jamie@example.test', subscribed_at: 2.days.ago, unsubscribed_at: 1.day.ago)
    consent = contact.attributes.slice('subscribed_at', 'unsubscribed_at')
    entry = stage
    original = entry.original.deep_dup
    accepted = @intake.process!(entry.id, lock_version: entry.lock_version, values: {name: 'Reviewed Jamie', company: 'Reviewed company'})
    assert_equal 'imported', accepted.status
    assert_equal 'Reviewed Jamie', accepted.lead.name
    assert_equal @member.id, accepted.lead.owner_id
    assert_equal original, accepted.original
    assert_equal @member.id, LightekSales::Task.last.owner_id
    assert_equal consent, contact.reload.attributes.slice('subscribed_at', 'unsubscribed_at')
    assert_equal accepted.id, @intake.process!(entry.id, lock_version: 0).id
    assert_equal 1, LightekSales::Lead.count
    assert_equal 1, LightekSales::Task.count
    assert_equal 1, LightekSales::Activity.where(kind: 'inquiry_received').count
  end
  def test_intake_duplicate_converted_leads_keep_history_and_attach_next_task_to_deal
    prospect = lead
    opportunity = @workspace.convert!(prospect.id, {name: 'Existing deal', close_on: Date.current}, lock_version: prospect.lock_version)
    entry = stage(name: 'Different submitted name')
    result = @intake.process!(entry.id, lock_version: entry.lock_version)
    assert_equal 'duplicate', result.status
    assert_equal prospect.id, result.lead_id
    assert_equal 'Jamie Buyer', prospect.reload.name
    assert_equal 'qualified', opportunity.stage
    assert_equal opportunity, LightekSales::Task.last.record
    assert_equal 1, LightekSales::Lead.count
    assert_equal 1, LightekSales::Opportunity.count
  end
  def test_intake_invalid_acceptance_rolls_back_then_can_be_fixed_or_ignored
    entry = stage(email: 'invalid')
    assert_raises(ArgumentError) { @intake.process!(entry.id, lock_version: 0) }
    assert_equal 0, LightekSales::Lead.count
    assert_equal 0, LightekSales::Task.count
    assert_equal 'awaiting_review', entry.reload.status
    assert_raises(ActiveRecord::StaleObjectError) { @intake.process!(entry.id, lock_version: 99) }
    accepted = @intake.process!(entry.id, lock_version: 0, values: {email: 'fixed@example.test'})
    assert_equal 'imported', accepted.status
    assert_raises(ArgumentError) { @intake.ignore!(accepted.id, lock_version: accepted.lock_version) }
    ignored = stage(email: 'ignore@example.test')
    @intake.ignore!(ignored.id, lock_version: 0)
    assert_equal 'ignored', ignored.reload.status
    assert_equal ignored, @intake.process!(ignored.id, lock_version: 0)
    assert_equal 1, LightekSales::Lead.count
  end
  def test_intake_opt_in_automation_and_duplicate_jobs_are_idempotent_and_metered_once
    rule
    request = inquiry
    assert_includes ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] }, LightekSales::IntakeJob
    LightekSales::IntakeJob.perform_now(request.id)
    assert_equal 1, LightekSales::Lead.count
    assert_equal 1, LightekSales::Task.count
    assert_equal 'imported', LightekSales::IntakeEntry.last.status
    assert_equal 1, LightekAgency::PackagePolicy.reserved
    LightekSales::IntakeJob.perform_now(request.id)
    assert_equal 1, LightekSales::Task.count
    assert_equal 1, LightekAgency::PackagePolicy.reserved
    assert_equal 0, LightekAgency::PackagePolicy.released
  end
  def test_intake_automation_invalid_mapping_values_stay_visible_and_release_usage
    rule(mapping: {'name' => 'topic', 'email' => 'email', 'message' => 'msg'})
    request = inquiry
    LightekSales::IntakeJob.perform_now(request.id)
    entry = LightekSales::IntakeEntry.find_by!(inquiry: request)
    assert_equal 'needs_review', entry.status
    assert_match(/Enter a name/, entry.error_message)
    assert_equal 0, LightekSales::Lead.count
    assert_equal 0, LightekSales::Task.count
    assert_equal 1, LightekAgency::PackagePolicy.reserved
    assert_equal 1, LightekAgency::PackagePolicy.released
    LightekSales::IntakeJob.perform_now(request.id)
    assert_equal 1, LightekAgency::PackagePolicy.reserved
    @intake.process!(entry.id, lock_version: entry.lock_version, values: {name: 'Reviewed name'})
    assert_equal 'imported', entry.reload.status
  end
  def test_intake_disabled_historical_and_package_denied_requests_never_create_leads
    historical = inquiry
    configured = rule
    LightekSales::IntakeJob.perform_now(historical.id)
    assert_equal 0, LightekSales::IntakeEntry.count
    fresh = inquiry(email: 'fresh@example.test')
    LightekAgency::PackagePolicy.allowed = false
    LightekSales::IntakeJob.perform_now(fresh.id)
    assert_equal 'needs_review', LightekSales::IntakeEntry.last.status
    assert_equal 0, LightekSales::Lead.count
    assert_equal 0, LightekAgency::PackagePolicy.reserved
    @intake.save_rule!({enabled: false}, id: configured.id, lock_version: configured.lock_version)
    disabled_request = inquiry(email: 'disabled@example.test')
    LightekSales::IntakeJob.perform_now(disabled_request.id)
    assert_equal 1, LightekSales::IntakeEntry.count
  end
  def test_intake_recovery_sweep_finds_missed_dispatch_but_skips_old_and_other_site_forms
    inquiry(email: 'historical@example.test')
    rule
    fresh = inquiry
    inquiry(@foreign_site, email: 'other@example.test')
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    LightekSales::IntakeSweepJob.perform_now
    assert_equal [[fresh.id]], ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == LightekSales::IntakeJob }.map { |j| j[:args] }
    LightekSales::IntakeJob.perform_now(fresh.id)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    LightekSales::IntakeSweepJob.perform_now
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
  end
  def test_intake_rules_require_owner_published_form_and_installed_mapping
    assert_raises(ArgumentError) { @intake.save_rule!({template_key: 'music-nova-raye', section_key: 'contact', mapping: {'name' => 'name', 'email' => 'email'}, enabled: true}) }
    publish_form
    assert_raises(ActiveRecord::RecordInvalid) { rule(mapping: {'name' => 'private', 'email' => 'email'}) }
    member_intake = LightekSales::Intake.new(actor: @member, site: @site)
    assert_raises(ActiveRecord::RecordNotFound) { member_intake.save_rule!({enabled: true}) }
    request = inquiry(@foreign_site)
    assert_raises(ActiveRecord::RecordNotFound) { @intake.capture!(request.id) }
  end
  def test_intake_tasks_complete_snooze_stale_versions_and_revocation
    row = task
    service = LightekSales::Tasks.new(actor: @owner, site: @site)
    assert_equal row, service.create!(kind: 'lead', id: row.record_id, values: {}, source_key: row.source_key)
    assert_equal 1, LightekSales::Task.count
    service.update!(row.id, action: 'snooze', lock_version: row.lock_version, due_at: (Time.current + 2.days).iso8601)
    assert row.reload.due_at.future?
    assert row.snoozed_at
    assert_raises(ActiveRecord::StaleObjectError) { service.update!(row.id, action: 'complete', lock_version: 0) }
    assert_raises(ArgumentError) { service.update!(row.id, action: 'snooze', lock_version: row.lock_version, due_at: 1.day.ago.iso8601) }
    LightekAgency::SiteMembership.where(user: @member).delete_all
    service.update!(row.id, action: 'complete', lock_version: row.lock_version)
    assert_equal 'completed', row.reload.status
    assert_equal @owner, row.completed_by
    assert_equal @member, row.owner
    assert_equal 1, LightekSales::Activity.where(kind: 'task_completed').count
    assert_raises(ActiveRecord::RecordNotFound) { LightekSales::Tasks.new(actor: @member, site: @site) }
  end
  def test_intake_nevaeh_manages_tasks_with_site_scope_and_current_versions
    row = task
    commands = NevaehOs::PlatformActions
    status = nevaeh_service_command("Check sales task ##{row.id} on site ##{@site.id}")
    result = commands.perform!(actor: @member, command: status, action_id: 11)
    assert_equal 'open', result.fetch('task_status')
    assert_equal row.lock_version, result.fetch('lock_version')
    assert_raises(ActiveRecord::RecordNotFound) { commands.perform!(actor: @other, command: status, action_id: 12) }

    phrase = "sales task ##{row.id} on site ##{@site.id} at version #{row.lock_version}"
    complete = nevaeh_service_command("Complete #{phrase}")
    snooze_until = 2.days.from_now.change(usec: 0).iso8601
    snooze = nevaeh_service_command("Snooze #{phrase} until #{snooze_until}")
    result = commands.perform!(actor: @member, command: snooze, action_id: 13)
    assert_equal Time.iso8601(snooze_until), Time.iso8601(result.fetch('due_at'))
    assert_raises(ActiveRecord::StaleObjectError) { commands.perform!(actor: @member, command: complete, action_id: 14) }

    complete['payload']['lock_version'] = result.fetch('lock_version')
    assert_equal 'completed', commands.perform!(actor: @member, command: complete, action_id: 15).fetch('task_status')
    assert_equal @member, row.reload.completed_by
    assert_equal 1, LightekSales::Activity.where(kind: 'task_completed').count

    due = 3.days.from_now.change(usec: 0).iso8601
    schedule = nevaeh_service_command("Schedule a follow-up called \"Send notes\" for lead ##{row.record_id} on site ##{@site.id} assigning user ##{@member.id} due #{due}")
    next_task = commands.perform!(actor: @owner, command: schedule, action_id: 16)
    assert_equal next_task, commands.perform!(actor: @owner, command: schedule, action_id: 16)
    second = LightekSales::Task.find(next_task.fetch('task_id'))
    assert_equal @member, second.owner
    cancel = nevaeh_service_command("Cancel sales task ##{second.id} on site ##{@site.id} at version #{second.lock_version}")
    assert_equal 'canceled', commands.perform!(actor: @owner, command: cancel, action_id: 16).fetch('task_status')
  end
  def test_intake_task_calendar_escapes_injection_and_preserves_unicode_fold_boundaries
    row = task(title: "Review éééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé; client, scope\r\nATTENDEE:evil@example.test")
    calendar = LightekSales::TaskCalendar.call(row)
    assert calendar.valid_encoding?
    assert calendar.lines.all? { |line| line.delete_suffix("\r\n").bytesize <= 75 }
    refute_includes calendar, "\r\nATTENDEE:"
    assert_includes calendar, '\\; client\\, scope\\nATTENDEE'
    assert_includes calendar, "DTSTART:#{row.due_at.utc.strftime('%Y%m%dT%H%M%SZ')}"
    get calendar_dashboard_sales_task_path(id: row.id, site_id: @site.id), headers: headers
    assert_response :ok
    assert_match(/attachment/, response.headers['Content-Disposition'])
    assert_raises(ActiveRecord::RecordNotFound) { get calendar_dashboard_sales_task_path(id: row.id, site_id: @site.id), headers: headers(@other) }
  end
  def test_intake_http_review_upload_rules_and_tasks_are_scoped_and_csrf_protected
    request = inquiry
    csrf = token
    post capture_dashboard_sales_intake_path(site_id: @site.id), params: {inquiry_id: request.id}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    entry = LightekSales::IntakeEntry.last
    get response.location, headers: headers
    assert_response :ok
    assert_includes response.body, 'Confirm the essentials'
    post accept_dashboard_sales_intake_path(site_id: @site.id, id: entry.id), params: {entry: {lock_version: entry.lock_version, name: 'Jamie', email: 'jamie@example.test'}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_equal 'imported', entry.reload.status
    get dashboard_sales_path(site_id: @site.id, tab: 'tasks'), headers: headers
    assert_response :ok
    assert_includes response.body, 'Review new inquiry from Jamie'
    row = LightekSales::Task.last
    patch dashboard_sales_task_path(site_id: @site.id, id: row.id), params: {task: {action: 'complete', lock_version: row.lock_version}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_equal 'completed', row.reload.status
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post capture_dashboard_sales_intake_path(site_id: @site.id), params: {inquiry_id: request.id}, headers: headers
    end
    assert_raises(ActiveRecord::RecordNotFound) { get dashboard_sales_intake_entry_path(site_id: @site.id, id: entry.id), headers: headers(@other) }
    assert_equal 'commerce', LightekAgency::PackageFeatures.for_controller('dashboard/sales_intake')
    assert_equal 'commerce', LightekAgency::PackageFeatures.for_controller('dashboard/sales_tasks')
  end
  def test_intake_http_configuration_disable_after_unpublish_and_manual_task_retries
    page = publish_form
    csrf = token
    post configure_dashboard_sales_intake_path(site_id: @site.id), params: {form_key: 'music-nova-raye::contact', rule: {source: 'website', enabled: '1', mapping: {name: 'name', email: 'email', message: 'msg'}}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    configured = LightekSales::IntakeRule.last
    assert configured.enabled?
    page.update!(published: false)
    post configure_dashboard_sales_intake_path(site_id: @site.id), params: {form_key: 'music-nova-raye::contact', rule_id: configured.id, lock_version: configured.lock_version, rule: {enabled: '0'}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    refute configured.reload.enabled?
    member_token = token(@member)
    assert_raises(ActiveRecord::RecordNotFound) do
      post configure_dashboard_sales_intake_path(site_id: @site.id), params: {form_key: 'music-nova-raye::contact', rule: {enabled: '0'}}, headers: headers(@member).merge('X-CSRF-Token' => member_token)
    end
    prospect = lead
    values = {record_kind: 'lead', record_id: prospect.id, request_key: 'stable-request', task: {title: 'Speak with buyer', owner_id: @member.id, due_at: (Time.current + 1.day).iso8601}}
    2.times do
      post dashboard_sales_tasks_path(site_id: @site.id), params: values, headers: headers.merge('X-CSRF-Token' => csrf)
      assert_response :see_other
    end
    assert_equal 1, LightekSales::Task.count
    row = LightekSales::Task.last
    patch dashboard_sales_task_path(site_id: @site.id, id: row.id), params: {task: {action: 'cancel', lock_version: row.lock_version}}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_equal 'canceled', row.reload.status
  end
  def test_intake_native_views_and_csv_upload_render_for_browser_acceptance
    publish_form
    request = inquiry(name: '<script>unsafe</script>')
    entry = @intake.capture!(request.id)
    task
    get dashboard_sales_intake_path(site_id: @site.id), headers: headers
    assert_response :ok
    assert_includes response.body, 'Automatic form intake'
    export('intake')
    get dashboard_sales_intake_entry_path(site_id: @site.id, id: entry.id), headers: headers
    assert_response :ok
    assert_includes response.body, '&lt;script&gt;unsafe&lt;/script&gt;'
    refute_includes response.body, '<script>unsafe</script>'
    export('inquiry')
    get dashboard_sales_path(site_id: @site.id, tab: 'tasks'), headers: headers
    assert_response :ok
    export('tasks')
    csrf = token
    tempfile = Tempfile.new(['sales-intake', '.csv'])
    tempfile.write("name,email\nUpload,upload@example.test\n"); tempfile.close
    post upload_dashboard_sales_intake_path(site_id: @site.id), params: {file: Rack::Test::UploadedFile.new(tempfile.path, 'text/csv')}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_equal 2, LightekSales::IntakeEntry.count
  ensure
    tempfile&.unlink
  end
  def export(name)
    return unless ENV['SALES_PREVIEW_DIR']
    FileUtils.mkdir_p(ENV['SALES_PREVIEW_DIR'])
    File.write(File.join(ENV['SALES_PREVIEW_DIR'], "#{name}.html"), response.body)
  end
end
