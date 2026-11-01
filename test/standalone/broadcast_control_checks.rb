# frozen_string_literal: true
require_relative "pwa_http_checks"
require File.join(ROOT, "db/migrate/20261101010000_create_studio_broadcast_control")
CreateStudioBroadcastControl.new.migrate(:up)
%w[app/models/studio/broadcasting/application app/models/studio/broadcasting/channel app/models/studio/broadcasting/program
   app/services/studio/broadcasting/access app/services/studio/broadcasting/experience
   app/services/gatekeeper/studio_live_policy app/services/studio/live/destination app/services/studio/live/encoder app/services/studio/live/sessions].each { |file| require File.join(ROOT, file) }
%w[app/services/studio/gatekeeper/client app/services/studio/publishers/lightek_streaming app/services/studio/publishers/registry app/services/studio/publishing/dispatch app/jobs/studio_publication_dispatch_job].each { |file| require File.join(ROOT, file) }
class User
  def can_access_feature?(_key) = false
end
class ApplicationController
  helper_method :current_user
  def resume_session = nil
end
module Dashboard; end
module DymondDash
  class ApplicationController < ::ApplicationController; end
end
require File.join(ROOT, "app/controllers/dashboard/settings_home_controller")
require File.join(ROOT, "app/controllers/dashboard/media_studio_controller")
require File.join(ROOT, "app/controllers/dashboard/live_broadcasts_controller")
require File.join(ROOT, "app/controllers/gatekeeper_controller")
Dashboard::MediaStudioController.prepend_view_path(File.join(ROOT, "app/views"))
Dashboard::LiveBroadcastsController.prepend_view_path(File.join(ROOT, "app/views"))
# Host engine layouts/auth are not part of the standalone runtime.
Dashboard::MediaStudioController.layout false
Dashboard::LiveBroadcastsController.layout false
Rails.application.routes.append do
  get "/dashboard/studio-broadcasting", to: "dashboard/media_studio#index", as: :dashboard_media_studio
  post "/dashboard/studio-broadcasting/generation-provider", to: "dashboard/media_studio#save_generation_provider", as: :dashboard_studio_generation_provider
  post "/dashboard/studio-broadcasting/applications", to: "dashboard/media_studio#save_application", as: :dashboard_broadcast_applications
  patch "/dashboard/studio-broadcasting/applications/:id", to: "dashboard/media_studio#save_application", as: :dashboard_broadcast_application
  post "/dashboard/studio-broadcasting/channels", to: "dashboard/media_studio#save_channel", as: :dashboard_broadcast_channels
  patch "/dashboard/studio-broadcasting/channels/:id", to: "dashboard/media_studio#save_channel", as: :dashboard_broadcast_channel
  post "/dashboard/studio-broadcasting/programs", to: "dashboard/media_studio#schedule", as: :dashboard_broadcast_programs
  delete "/dashboard/studio-broadcasting/programs/:id", to: "dashboard/media_studio#remove_program", as: :dashboard_broadcast_program
  patch "/dashboard/studio-broadcasting/posts/:id", to: "dashboard/media_studio#update_post", as: :dashboard_broadcast_post
  post "/dashboard/studio-broadcasting/publications", to: "dashboard/media_studio#publish", as: :dashboard_broadcast_publications
  delete "/dashboard/studio-broadcasting/publications/:id", to: "dashboard/media_studio#cancel_publication", as: :dashboard_broadcast_publication
  post "/dashboard/studio-broadcasting/live/:id/stop", to: "dashboard/media_studio#stop_live", as: :stop_dashboard_broadcast
  get "/dashboard/live", to: "dashboard/live_broadcasts#index", as: :dashboard_live
  post "/dashboard/live/sessions", to: "dashboard/live_broadcasts#create", as: :dashboard_live_sessions
  post "/dashboard/live/destination", to: "dashboard/live_broadcasts#destination", as: :dashboard_live_destination
  get "/dashboard/live/:id/recording", to: "dashboard/live_broadcasts#recording", as: :dashboard_live_recording
  get "/gatekeeper", to: "gatekeeper#index"
  get "/gatekeeper/config", to: "gatekeeper#platform_config"
  get "/gatekeeper/content/:id", to: "gatekeeper#content"
  get "/gatekeeper/screens/live", to: "gatekeeper#live"
  get "/gatekeeper/search", to: "gatekeeper#search"
end
Rails.application.reload_routes!
class BroadcastControlTest < PwaHttpIntegrationTest
  PwaHttpIntegrationTest.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @alice.update!(role: "super_admin")
    @outlet = Studio::Broadcasting::Application.create!(site: @site, slug: "octavia", name: "Octavia", platform: "roku", status: "published")
    Dashboard::MediaStudioController.allow_forgery_protection = false
  end
  def teardown
    Dashboard::MediaStudioController.allow_forgery_protection = true
    super
  end
  def video(site = @site, **attrs)
    post = Post.create!({user: @alice, site: site, title: "A real studio release", kind: "video", distribution: "octavia", content: "Premiere"}.merge(attrs))
    post.media.attach(io: StringIO.new("0123456789"), filename: "master.mp4", content_type: "video/mp4", identify: false)
    post
  end
  def experience(user = nil, **opts)
    Studio::Broadcasting::Experience.new(site: @site, user: user, platform: "roku", origin: "https://lightek.test", **opts)
  end
  def test_gatekeeper_reads_published_media_with_real_playback_contract_and_controls
    post = video
    client = session_for
    client.get "/gatekeeper/config"
    assert_equal 200, client.response.status
    assert_kind_of Hash, body(client).dig("theme", "colors")
    assert_equal "Octavia", body(client).dig("application", "name")
    client.get "/gatekeeper"
    assert_equal post.id.to_s, body(client).dig("rows", 0, "items", 0, "content_id")
    client.get "/gatekeeper/content/#{post.id}"
    assert_equal 200, client.response.status
    action = body(client).dig("details", "actions", 0)
    assert_equal "mp4", action["stream_format"]
    assert_includes action["playback_url"], "/api/lightek/pwa/posts/#{post.id}/media/"
    assert_equal "private, no-store", client.response.headers["Cache-Control"]
    @outlet.update!(settings: {"catalog"=>false})
    client.get "/gatekeeper/content/#{post.id}"
    assert_equal 404, client.response.status
    client.get "/gatekeeper"
    assert_empty body(client)["rows"]
  end
  def test_gatekeeper_never_leaks_other_sites_private_or_gender_restricted_programs
    visible = video
    video(@other_site)
    video(@site, visibility: "private")
    video(@site, audience: "women")
    hidden = video(@site, moderation_state: "hidden")
    @alice.update!(role: "client")
    assert_equal [visible.id.to_s], experience.home[:rows].first[:items].map { |item| item[:id] }
    assert_raises(ActiveRecord::RecordNotFound) { experience.content(hidden.id) }
    @outlet.update!(status: "maintenance")
    assert_empty experience.home[:rows]
    assert_raises(ActiveRecord::RecordNotFound) { experience.content(visible.id) }
  end
  def test_controls_and_app_keys_are_scoped_per_platform_and_site
    second = Studio::Broadcasting::Application.create!(site: @site, slug: "news", name: "News", platform: "roku", status: "published", settings: {"search"=>false, "accent"=>"#ABCDEF"})
    assert_equal "#ABCDEF", experience(nil, slug: "news").config.dig(:theme, :colors, :primary)
    assert_equal false, experience(nil, slug: "news").config.dig(:controls, "search")
    refute experience(nil, slug: "news").home[:navigation][:items].any? { |n| n[:id] == "nav-search" }
    assert_raises(ActiveRecord::RecordNotFound) { experience(nil, slug: "missing") }
    second.settings = {"search"=>"yes"}
    refute second.valid?
    refute Studio::Broadcasting::Application.new(site: @site, slug: "x", name: "X", settings: {"accent"=>"<script>"}).valid?
  end
  def test_each_ott_app_can_curate_its_own_titles_and_channels
    selected = video
    video(@site, title: "Another release")
    chosen = Studio::Broadcasting::Channel.create!(site: @site, name: "Selected TV", status: "published", playback_url: "https://media.example/selected.m3u8")
    Studio::Broadcasting::Channel.create!(site: @site, name: "Other TV", status: "published", playback_url: "https://media.example/other.m3u8")
    client = session_for
    client.patch "/dashboard/studio-broadcasting/applications/#{@outlet.id}?site_id=#{@site.id}", headers: headers,
      params: {outlet: {settings: {catalog_source: "selected", post_ids: ["", selected.id.to_s], channel_source: "selected", channel_ids: [chosen.id.to_s]}}}
    assert_equal 303, client.response.status
    assert_equal "selected", @outlet.reload.configuration["channel_source"], @outlet.settings.inspect
    rows = experience.home[:rows]
    assert_equal ["Selected TV"], rows.first[:items].map { |item| item[:title] }
    assert_equal [selected.id.to_s], rows.last[:items].map { |item| item[:id] }
    @outlet.reload.settings = {"post_ids"=>[video(@other_site).id]}
    refute @outlet.valid?
  end

  def test_channels_and_program_guide_exclude_hidden_or_foreign_titles_and_prevent_overlap
    post = video
    channel = Studio::Broadcasting::Channel.create!(site: @site, name: "Lightek TV", status: "published", playback_url: "https://media.example/live.m3u8")
    now = Time.current
    slot = channel.programs.create!(post: post, starts_at: now - 60, ends_at: now + 60)
    assert_equal "LIVE", experience.home[:rows].first[:items].first[:badge]
    guide = experience.home[:rows].find { |row| row[:id] == "program-guide" }
    assert_equal "On now", guide[:items].first[:subtitle]
    assert_raises(ActiveRecord::RecordInvalid) { channel.programs.create!(post: post, starts_at: now, ends_at: now + 120) }
    assert_raises(ActiveRecord::RecordInvalid) { channel.programs.create!(post: video(@other_site), starts_at: now + 120, ends_at: now + 180) }
    post.update!(moderation_state: "hidden")
    refute experience.home[:rows].any? { |row| row[:id] == "program-guide" }
    channel.update!(status: "off_air")
    assert_empty experience.home[:rows]
    assert slot.persisted?
  end
  def test_dashboard_renders_complete_control_room_and_saved_controls_reach_gatekeeper
    video
    client = session_for
    client.get "/dashboard/studio-broadcasting?site_id=#{@site.id}", headers: headers.merge("Accept"=>"text/html")
    assert_equal 200, client.response.status, client.response.body.first(1000)
    assert_includes client.response.body, "OTT applications"
    assert_includes client.response.body, "Media & releases"
    File.write(ENV["BROADCAST_PREVIEW_HTML"], client.response.body) if ENV["BROADCAST_PREVIEW_HTML"]
    client.patch "/dashboard/studio-broadcasting/applications/#{@outlet.id}?site_id=#{@site.id}", headers: headers,
      params: {outlet: {name: "Octavia Television", lock_version: @outlet.lock_version, settings: {accent: "#FFD700", captions: "0", configuration_ttl: "30"}}}
    assert_equal 303, client.response.status
    assert_equal "Octavia Television", experience.config.dig(:application, :name)
    assert_equal false, experience.config.dig(:controls, "captions")
    assert_equal 30, experience.config.dig(:refresh, :configuration_ttl_seconds)
  end
  def test_site_owner_can_manage_own_outlet_but_cannot_spoof_another_site
    @site.update!(tenant: @alice)
    @alice.update!(role: "client")
    foreign = Studio::Broadcasting::Application.create!(site: @other_site, name: "Other", slug: "other")
    client = session_for
    client.get "/dashboard/studio-broadcasting?site_id=#{@site.id}", headers: headers.merge("Accept"=>"text/html")
    assert_equal 200, client.response.status
    client.patch "/dashboard/studio-broadcasting/applications/#{foreign.id}?site_id=#{@site.id}", headers: headers, params: {outlet: {name: "Stolen"}}
    assert_equal 404, client.response.status
    client.get "/dashboard/studio-broadcasting?site_id=#{@other_site.id}", headers: headers.merge("Accept"=>"text/html")
    assert_equal 404, client.response.status
    assert_equal "Other", foreign.reload.name
  end
  def test_live_studio_keeps_hostname_based_site_resolution
    client = session_for
    Studio::Live::Destination.stub(:configured?, false) do
      client.get "/dashboard/live", headers: headers.merge("Accept"=>"text/html")
      assert_equal 200, client.response.status, client.response.body.first(1000)
      assert_includes client.response.body, "Lightek / OTT + Restream"
      refute_includes client.response.body, "Choose an application for Lightek broadcasting"
    end
    Dashboard::LiveBroadcastsController.allow_forgery_protection = false
    client.post "/dashboard/live/sessions", headers: headers,
      params: {title: "Host-bound broadcast", destination: "lightek", site_id: @other_site.id}, as: :json
    assert_equal 201, client.response.status, client.response.body
    operation = StudioLiveOperation.find(body(client).fetch("id"))
    assert_equal @site.id, operation.studio_project.site_id
  ensure
    Dashboard::LiveBroadcastsController.allow_forgery_protection = true
  end
  def test_simulcast_creates_authorized_lightek_post_without_exposing_credentials
    Studio::Live::Destination.stub(:configured?, true) do
      operation = Studio::Live::Sessions.create!(user: @alice, title: "Multistream", destination: "simulcast", site: @site)
      post = Post.find(operation.metadata.fetch("post_id"))
      assert_equal @site.id, post.site_id
      assert_equal "lightek_streaming", post.distribution
      assert_equal "simulcast", operation.metadata["destination"]
      assert_equal "studio-live-#{@alice.id}-restream", operation.credential_ref
      refute operation.metadata.key?("stream_key")
    end
  end
  def test_dashboard_publication_reaches_the_same_gatekeeper_catalog_and_cancelled_release_stays_cancelled
    project = StudioProject.create!(site: @site, owner: @alice, name: "Dashboard film")
    operation = project.studio_operations.create!(operation_type: "edit_media", provider: "ffmpeg", capability: "studio.workspace.timeline.quote", status: "completed")
    artifact = operation.artifacts.create!(kind: "video", filename: "master.mp4")
    artifact.file.attach(io: StringIO.new("video master"), filename: "master.mp4", content_type: "video/mp4", identify: false)
    client = session_for
    payload = {artifact_id: artifact.id, platform: "octavia", title: "Dashboard premiere", request_key: SecureRandom.hex(16)}
    client.post "/dashboard/studio-broadcasting/publications?site_id=#{@site.id}", headers: headers, params: {publication: payload}
    assert_equal 303, client.response.status
    release = project.studio_publications.last
    assert release
    StudioPublicationDispatchJob.perform_now(release.id)
    assert_equal "published", release.reload.status
    assert_equal "Dashboard premiere", experience.home[:rows].first[:items].first[:title]
    StudioPublicationDispatchJob.perform_now(release.id)
    assert_equal 1, Post.where(request_key: "studio-publication-#{release.id}").count
    client.post "/dashboard/studio-broadcasting/publications?site_id=#{@site.id}", headers: headers,
      params: {publication: payload.merge(request_key: SecureRandom.hex(16), publish_at: 2.hours.from_now.iso8601)}
    queued = project.studio_publications.order(:id).last
    assert_equal "scheduled", queued.status
    client.delete "/dashboard/studio-broadcasting/publications/#{queued.id}?site_id=#{@site.id}", headers: headers
    assert_equal 303, client.response.status
    Studio::Publishing::Dispatch.new(queued).call
    assert_equal "cancelled", queued.reload.status
    refute Post.exists?(request_key: "studio-publication-#{queued.id}")
  end

  def test_real_encoder_generates_hls_and_restream_flv_outputs_from_one_capture
    Dir.mktmpdir("simulcast-") do |dir|
      source = File.join(dir, "capture.webm")
      _out, error, status = Open3.capture3("ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "4", "-c:v", "libvpx", "-deadline", "realtime", "-c:a", "libopus", source)
      assert status.success?, error
      events = Queue.new
      hls = File.join(dir, "index.m3u8")
      relay = File.join(dir, "relay.flv")
      encoder = Studio::Live::Encoder.new(output: hls, hls: true, test: false, relay_output: relay,
        on_event: ->(event, failure) { events << [event, failure] }).start!
      File.binread(source).bytes.each_slice(24000).with_index do |bytes, index|
        encoder.append!(encoded: Base64.strict_encode64(bytes.pack("C*")), sequence: index)
      end
      encoder.stop!
      terminal = Timeout.timeout(10) { loop { event = events.pop; break event if %w[ended failed].include?(event.first) } }
      assert_equal ["ended", nil], terminal
      [hls, relay].each do |output|
        out, error, status = Open3.capture3("ffprobe", "-v", "error", "-show_streams", "-of", "json", output)
        assert status.success?, error
        streams = JSON.parse(out).fetch("streams")
        assert streams.any? { |stream| stream["codec_name"] == "h264" }
        assert streams.any? { |stream| stream["codec_name"] == "aac" }
      end
    ensure
      encoder&.stop!
    end
  end

  def test_stale_app_update_and_csrf_protection
    client = session_for
    @outlet.update!(name: "Newer")
    client.patch "/dashboard/studio-broadcasting/applications/#{@outlet.id}?site_id=#{@site.id}", headers: headers, params: {outlet: {name: "Older", lock_version: 0}}
    assert_equal 303, client.response.status
    assert_equal "Newer", @outlet.reload.name
    Dashboard::MediaStudioController.allow_forgery_protection = true
    client.post "/dashboard/studio-broadcasting/applications?site_id=#{@site.id}", headers: headers, params: {outlet: {name: "CSRF", slug: "csrf"}}
    assert_equal 422, client.response.status
    refute Studio::Broadcasting::Application.exists?(slug: "csrf")
  end
end
