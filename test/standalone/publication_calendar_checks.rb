# Production calendar/media services, schema, native controllers and job claims.
# Active Storage byte delivery and Studio project policy are boundary fixtures;
# no provider or external storage HTTP requests are made.
require_relative 'campaign_content_checks'
require_relative '../../app/services/nevaeh_os/platform_actions'
class ApplicationRecord
  def self.has_one_attached(*) = nil
end
ActiveRecord::Schema.define do
  create_table(:studio_projects) { |t| t.references :site; t.references :owner }
  create_table(:studio_operations) { |t| t.references :studio_project; t.string :status; t.json :metadata, default: {} }
  create_table(:artifacts) { |t| t.references :studio_operation; t.integer :creation_job_id; t.string :kind; t.string :filename }
  create_table(:calendar_test_blobs) { |t| t.string :content_type; t.string :checksum; t.bigint :byte_size }
  create_table(:calendar_test_attachments) { |t| t.string :record_type; t.integer :record_id; t.references :blob }
end
class StudioProject < ApplicationRecord; end
class StudioOperation < ApplicationRecord
  belongs_to :studio_project
end
require ROOT.join('app/models/artifact')
class CalendarTestBlob < ApplicationRecord; end
class CalendarTestAttachment < ApplicationRecord; end
class CalendarFile
  def initialize(record) = @record = record
  def scope = CalendarTestAttachment.where(record_type: @record.class.name, record_id: @record.id)
  def attached? = scope.exists?
  def blob = CalendarTestBlob.find(scope.first!.blob_id)
  def attach(blob)
    scope.delete_all
    scope.create!(blob_id: blob.id)
  end
end
require ROOT.join('db/migrate/20261115170000_add_campaign_publishing_calendar')
AddCampaignPublishingCalendar.new.migrate(:up)
LightekMarketing::Campaign.reset_column_information
%w[media_binding publication_slot].each { |file| require ROOT.join("app/models/lightek_marketing/#{file}") }
class Artifact; def file = CalendarFile.new(self); end
class LightekMarketing::MediaBinding; def file = CalendarFile.new(self); end
class Studio::PwaAccess
  def initialize(payload) = @payload = payload
  def projects = StudioProject.where(owner_id: @payload.fetch('user_id'))
end
%w[campaign_media publication_calendar tiktok_video_upload].each { |file| require ROOT.join("app/services/lightek_marketing/#{file}") }
module LightekVault; module Service; class AccessDenied < StandardError; end; end; end
%w[publication_slot_job publication_sweep_job tiktok_submission_poll_job].each { |file| require ROOT.join("app/jobs/lightek_marketing/#{file}") }
require ROOT.join('app/controllers/dashboard/publication_calendar_controller')
require ROOT.join('app/controllers/campaign_media_controller')
[Dashboard::PublicationCalendarController, CampaignMediaController].each { |c| c.prepend_view_path ROOT.join('app/views'); c.layout false }
# The full application supplies this helper through Active Storage's engine.
SalesHarness.routes.url_helpers.define_singleton_method(:rails_blob_url) { |file, **options| "https://#{options.fetch(:host)}/fixture-storage/#{file.blob.id}" }
SalesCrmChecks.prepend(Module.new do
  def setup
    LightekMarketing::PublicationSlot.delete_all
    LightekMarketing::Campaign.update_all(media_binding_id: nil)
    LightekMarketing::MediaBinding.delete_all
    [CalendarTestAttachment, CalendarTestBlob, Artifact, StudioOperation, StudioProject].each(&:delete_all)
    super
  end
end)
class PublicationCalendarChecks < CampaignContentChecks
  def self.runnable_methods = instance_methods.grep(/^test_calendar_/).map(&:to_s)
  def calendar(actor = @owner) = LightekMarketing::PublicationCalendar.new(actor: actor, site: @site)
  def media(actor = @owner) = LightekMarketing::CampaignMedia.new(actor: actor, site: @site)
  def connection
    LightekMarketing::SocialConnection.create!(site: @site, provider: 'facebook', account_label: "Page #{SecureRandom.hex(4)}", credential_key: 'fixture', publish_endpoint: 'https://graph.facebook.com')
  end
  def review(key: SecureRandom.uuid)
    brief unless LightekGrowth::Brief.exists?(site: @site)
    row = workbench.generate!(campaign_id: @campaign.id, request_key: key).first
    workbench.approve!(id: row.id, version: row.lock_version)
    @campaign.reload
  end
  def slot(connection: self.connection, key: SecureRandom.uuid)
    calendar.schedule!(campaign_id: @campaign.id, connection_id: connection.id, scheduled_at: 1.hour.from_now.iso8601, time_zone: 'UTC', request_key: key)
  end
  def artifact(site: @site, owner: @owner, type: 'image/png', status: 'completed', preview: false)
    project = StudioProject.create!(site_id: site.id, owner_id: owner.id)
    operation = StudioOperation.create!(studio_project: project, status: status, metadata: {'draft_preview' => preview})
    export = Artifact.create!(studio_operation: operation, kind: type.start_with?('video') ? 'video' : 'image', filename: 'finished-export')
    export.file.attach(CalendarTestBlob.create!(content_type: type, checksum: SecureRandom.hex(16), byte_size: 1000))
    export
  end
  def test_calendar_nevaeh_schedules_a_reviewed_campaign_once
    review
    destination = connection
    command = NevaehOs::PlatformActions.command('marketing.publication.schedule',
      {'site_id'=>@site.id, 'campaign_id'=>@campaign.id, 'connection_id'=>destination.id,
       'scheduled_at'=>1.hour.from_now.iso8601, 'time_zone'=>'UTC'})

    receipt = nil
    assert_difference 'LightekMarketing::PublicationSlot.count', 1 do
      receipt = NevaehOs::PlatformActions.perform!(actor: @owner, command: command, action_id: 123)
      replay = NevaehOs::PlatformActions.perform!(actor: @owner, command: command, action_id: 123)
      assert_equal receipt.fetch('slot_id'), replay.fetch('slot_id')
    end
    assert_equal 'scheduled', receipt.fetch('publication_status')
    slot = LightekMarketing::PublicationSlot.find(receipt.fetch('slot_id'))
    assert_equal @campaign.content_digest, slot.content_digest
    assert_nil slot.started_at
    assert_nil slot.social_post_id
  end

  def test_calendar_nevaeh_checks_and_cancels_only_the_authorized_current_slot
    review
    entry = slot
    check = nevaeh_sales_command("Check publication slot ##{entry.id} on site ##{@site.id}")
    result = NevaehOs::PlatformActions.perform!(actor: @owner, command: check, action_id: 1)
    assert_equal 'scheduled', result.fetch('publication_status')
    assert_equal entry.lock_version, result.fetch('lock_version')
    assert_nil result.fetch('provider_status')

    cancel = nevaeh_sales_command("Cancel publication slot ##{entry.id} on site ##{@site.id} at version #{entry.lock_version}")
    stale = cancel.merge('payload'=>cancel.fetch('payload').merge('lock_version'=>entry.lock_version + 1))
    assert_raises(ActiveRecord::StaleObjectError) { NevaehOs::PlatformActions.perform!(actor: @owner, command: stale, action_id: 2) }
    assert_raises(ArgumentError) { NevaehOs::PlatformActions.perform!(actor: @member, command: cancel, action_id: 3) }
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::PlatformActions.perform!(actor: @other, command: cancel, action_id: 4) }
    assert_no_difference 'LightekMarketing::SocialPost.count' do
      canceled = NevaehOs::PlatformActions.perform!(actor: @owner, command: cancel, action_id: 5)
      assert_equal 'canceled', canceled.fetch('publication_status')
      assert_equal canceled, NevaehOs::PlatformActions.perform!(actor: @owner, command: cancel, action_id: 6)
    end
  end

  def test_calendar_reviewed_schedule_is_idempotent_and_worker_publishes_once
    review
    destination = connection
    entry = slot(connection: destination, key: 'calendar-test-slot-1')
    assert_equal entry, calendar.schedule!(campaign_id: @campaign.id, connection_id: destination.id, scheduled_at: entry.scheduled_at.iso8601, time_zone: 'UTC', request_key: 'calendar-test-slot-1')
    assert_raises(ArgumentError) { slot(connection: destination) }
    calls = 0
    travel 2.hours do
      2.times { LightekMarketing::PublicationSweepJob.perform_now }
      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == LightekMarketing::PublicationSlotJob }
      assert_equal 1, jobs.size
      LightekMarketing::SocialProviders.stub(:publish!, ->(**) { calls += 1; 'published-reference' }) do
        2.times { LightekMarketing::PublicationSlotJob.perform_now(entry.id) }
      end
    end
    assert_equal 1, calls
    assert_equal 'published', entry.reload.status
    assert_equal 'published-reference', entry.social_post.remote_id
    assert_raises(ArgumentError) { calendar.cancel!(id: entry.id, version: entry.lock_version) }
    get dashboard_publication_calendar_path(site_id: @site.id, campaign_id: @campaign.id), headers: headers
    assert_response :success
    assert_select 'h1', text: 'Publishing calendar'
    assert_includes response.body, 'published-reference'
    File.write(File.join(ENV['SALES_PREVIEW_DIR'], 'publishing.html'), response.body) if ENV['SALES_PREVIEW_DIR']
  end
  def test_calendar_changed_copy_disconnected_or_revoked_actor_blocks_before_io
    review
    entry = slot
    @campaign.update!(message: 'Changed copy')
    travel 2.hours do
      LightekMarketing::PublicationSlotJob.perform_now(entry.id)
    end
    assert_equal 'blocked', entry.reload.status
    assert_nil entry.started_at
    assert_equal 0, LightekMarketing::SocialPost.count
    calendar.cancel!(id: entry.id, version: entry.lock_version)
    review
    destination = connection
    entry = slot(connection: destination)
    destination.update!(enabled: false)
    travel 2.hours do
      LightekMarketing::PublicationSlotJob.perform_now(entry.id)
    end
    assert_equal 'blocked', entry.reload.status
    @owner.update!(access_suspended_at: Time.current)
    another = LightekMarketing::PublicationSlot.create!(site: @site, campaign: @campaign, connection: self.connection, scheduled_by: @owner, scheduled_at: Time.current - 1.minute, request_key: 'revoked-scheduler', content_digest: @campaign.content_digest)
    LightekMarketing::PublicationSlotJob.perform_now(another.id)
    assert_equal 'blocked', another.reload.status
    assert_equal 0, LightekMarketing::SocialPost.count
  end
  def test_calendar_unknown_provider_outcome_is_never_automatically_retried
    review
    entry = slot
    calls = 0
    travel 2.hours do
      LightekMarketing::SocialProviders.stub(:publish!, ->(**) { calls += 1; raise Timeout::Error, 'ambiguous outcome' }) do
        assert_raises(Timeout::Error) { LightekMarketing::PublicationSlotJob.perform_now(entry.id) }
        LightekMarketing::PublicationSlotJob.perform_now(entry.id)
        LightekMarketing::PublicationSweepJob.perform_now
      end
    end
    assert_equal 1, calls
    assert_equal 'needs_review', entry.reload.status
    assert_equal 'needs_review', entry.social_post.reload.status
    assert entry.started_at
    assert_equal 1, LightekMarketing::SocialPost.count
    assert_raises(ArgumentError) { calendar.cancel!(id: entry.id, version: entry.lock_version) }
  end
  def test_calendar_tiktok_submission_and_later_publication_are_distinct
    @campaign.update!(media_url: 'https://verified.test/finished.mp4')
    review
    previous = ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS']
    ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS'] = 'verified.test'
    destination = LightekMarketing::SocialConnection.create!(site: @site, provider: 'tiktok', account_label: 'TikTok', credential_key: 'tiktok-fixture', publish_endpoint: 'https://open.tiktokapis.com')
    entry = slot(connection: destination)
    travel 2.hours do
      LightekMarketing::TiktokVideoUpload.stub(:submit!, ->(**) { 'inbox-submission-1' }) { LightekMarketing::PublicationSlotJob.perform_now(entry.id) }
    end
    assert_equal 'submitted', entry.reload.status
    refute_equal 'published', entry.social_post.status
    entry.social_post.update!(status: 'published')
    LightekMarketing::PublicationSweepJob.perform_now
    assert_equal 'published', entry.reload.status
  ensure
    previous ? ENV['LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS'] = previous : ENV.delete('LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS')
  end
  def test_calendar_finished_export_binding_preserves_blob_and_resets_approval
    review
    export = artifact
    binding = media.attach!(campaign_id: @campaign.id, artifact_id: export.id)
    assert_equal export.file.blob.id, binding.file.blob.id
    assert_equal binding, media.attach!(campaign_id: @campaign.id, artifact_id: export.id)
    assert_equal 'draft', @campaign.reload.status
    refute @campaign.content_approved?
    assert_equal binding.public_url, @campaign.media_url
    assert binding.public_url.end_with?('.png')
    assert binding.usable?
    host! @site.host
    get URI(binding.public_url).request_uri
    assert_response :redirect
    assert_equal "https://#{@site.host}/fixture-storage/#{binding.file.blob.id}", response.location
    host! @foreign_site.host
    assert_raises(ActiveRecord::RecordNotFound) { get URI(binding.public_url).request_uri }
    review
    destination = LightekMarketing::SocialConnection.create!(site: @site, provider: 'instagram', account_label: 'Instagram', credential_key: 'ig-fixture', publish_endpoint: 'https://graph.facebook.com')
    entry = slot(connection: destination)
    media.revoke!(id: binding.id)
    refute binding.reload.usable?
    travel 2.hours do
      LightekMarketing::PublicationSlotJob.perform_now(entry.id)
    end
    assert_equal 'blocked', entry.reload.status
    host! @site.host
    assert_raises(ActiveRecord::RecordNotFound) { get URI(binding.public_url).request_uri }
  end
  def test_calendar_export_scope_preview_file_identity_and_history_guards
    assert_raises(ActiveRecord::RecordNotFound) { media.attach!(campaign_id: @campaign.id, artifact_id: artifact(site: @foreign_site, owner: @other).id) }
    assert_raises(ActiveRecord::RecordNotFound) { media.attach!(campaign_id: @campaign.id, artifact_id: artifact(status: 'running').id) }
    assert_raises(ArgumentError) { media.attach!(campaign_id: @campaign.id, artifact_id: artifact(preview: true).id) }
    assert_raises(ArgumentError) { media.attach!(campaign_id: @campaign.id, artifact_id: artifact(type: 'application/octet-stream').id) }
    export = artifact
    binding = media.attach!(campaign_id: @campaign.id, artifact_id: export.id)
    assert_raises(ActiveRecord::RecordInvalid) { binding.update!(source_snapshot: {}) }
    binding.file.attach(CalendarTestBlob.create!(content_type: 'image/png', checksum: 'different-file', byte_size: 100))
    refute binding.usable?
    @campaign.reload
    refute @campaign.media_ready?
    assert_raises(ArgumentError) { review }
  end
  def test_calendar_local_time_offsets_dst_role_and_native_csrf
    parsed = LightekMarketing::PublicationCalendar.parse_local(value: '2026-11-16T10:30', zone: 'America/New_York')
    assert_equal '2026-11-16T10:30:00-05:00', parsed
    assert_raises(ArgumentError) { LightekMarketing::PublicationCalendar.parse_local(value: '2027-03-14T02:30', zone: 'America/New_York') }
    assert_raises(ArgumentError) { LightekMarketing::PublicationCalendar.parse_local(value: '2026-11-01T01:30', zone: 'America/New_York') }
    review
    assert_raises(ArgumentError) { calendar(@member).schedule!(campaign_id: @campaign.id, connection_id: connection.id, scheduled_at: 1.hour.from_now.iso8601, request_key: 'not-a-publisher') }
    assert_raises(ActiveRecord::RecordNotFound) { calendar(@other).schedule!(campaign_id: @campaign.id, connection_id: connection.id, scheduled_at: 1.hour.from_now.iso8601, request_key: 'foreign-publisher') }
    assert_raises(ActionController::InvalidAuthenticityToken) { post dashboard_publication_calendar_path(site_id: @site.id), headers: headers }
    destination = connection
    csrf = token
    post dashboard_publication_calendar_path(site_id: @site.id), params: {campaign_id: @campaign.id, connection_id: destination.id, request_key: 'native-publication', scheduled_local: 2.hours.from_now.utc.strftime('%Y-%m-%dT%H:%M'), time_zone: 'UTC'}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    entry = LightekMarketing::PublicationSlot.last
    patch cancel_publication_slot_path(site_id: @site.id, id: entry.id), params: {lock_version: entry.lock_version}, headers: headers.merge('X-CSRF-Token' => csrf)
    assert_response :see_other
    assert_equal 'canceled', entry.reload.status
    assert_equal 0, LightekMarketing::SocialPost.count
  end
  def test_calendar_queue_recovery_and_lost_claim_require_no_duplicate_submission
    review
    entry = slot
    travel 2.hours do
      LightekMarketing::PublicationSweepJob.perform_now
      first_requested = entry.reload.queue_requested_at
      travel 6.minutes
      LightekMarketing::PublicationSweepJob.perform_now
      assert_operator entry.reload.queue_requested_at, :>, first_requested
      assert_equal 2, ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == LightekMarketing::PublicationSlotJob }
      post = LightekMarketing::SocialPost.create!(campaign: @campaign, connection: entry.connection)
      entry.update!(status: 'dispatching', started_at: 20.minutes.ago, social_post: post)
      LightekMarketing::PublicationSweepJob.perform_now
      assert_equal 'needs_review', entry.reload.status
      LightekMarketing::PublicationSlotJob.perform_now(entry.id)
      assert_equal 'needs_review', post.reload.status
      post.update!(status: 'published', remote_id: 'late-provider-receipt')
      LightekMarketing::PublicationSweepJob.perform_now
      assert_equal 'published', entry.reload.status
    end
  end

  def test_calendar_media_is_bound_to_issuing_application_host
    export = artifact
    binding = media.attach!(campaign_id: @campaign.id, artifact_id: export.id, delivery_host: 'control.test')
    assert binding.public_url.start_with?('https://control.test/')
    host! 'control.test'
    get URI(binding.public_url).request_uri
    assert_response :redirect
    assert response.location.start_with?('https://control.test/fixture-storage/')
    host! @site.host
    assert_raises(ActiveRecord::RecordNotFound) { get URI(binding.public_url).request_uri }
  end

  def test_calendar_existing_content_approval_digest_survives_without_media_adoption
    old_payload = {'channel' => 'social', 'production_format' => 'portrait', 'headline' => 'Existing offer', 'message' => 'Existing approved body', 'cta_label' => 'Learn more', 'cta_url' => 'https://example.test/', 'media_url' => nil, 'mail_account_id' => nil, 'recipient_email' => nil}
    digest = Digest::SHA256.hexdigest(JSON.generate(old_payload))
    @campaign.update_columns(old_payload.merge('content_review_required' => true, 'approved_content_digest' => digest, 'content_approved_by_id' => @owner.id, 'content_approved_at' => Time.current, 'status' => 'ready'))
    assert @campaign.reload.content_approved?
    assert_equal digest, @campaign.content_digest
    media.attach!(campaign_id: @campaign.id, artifact_id: artifact.id)
    refute @campaign.reload.content_approved?
    refute_equal digest, @campaign.content_digest
  end

  def test_calendar_media_attachment_enrolls_legacy_ready_campaign_in_review
    @campaign.update!(status: 'ready')
    refute @campaign.content_review_required?
    media.attach!(campaign_id: @campaign.id, artifact_id: artifact.id)
    assert @campaign.reload.content_review_required?
    assert_equal 'draft', @campaign.status
    refute @campaign.content_approved?
    post = LightekMarketing::SocialPost.create!(campaign: @campaign, connection: connection)
    assert_raises(LightekMarketing::SocialDispatch::Unavailable) { LightekMarketing::SocialDispatch.call!(post: post) }
  end

end
