require_relative "campaign_studio_checks"
require File.join(ROOT, "app/jobs/studio_editor_export_job")
require "base64"
def Rails.root = Pathname(ROOT)

class StudioEditorsChecks < CampaignStudioChecks
  CampaignStudioChecks.instance_methods(false).grep(/^test_/).each { |method| undef_method(method) }
  def setup
    super
    @scene.update!(settings: @scene.settings.merge("editor_kind" => "video"))
    @photo = @project.studio_scenes.create!(name: "Artwork", settings: StudioScene.default_settings.merge("editor_kind" => "photo", "timeline" => {"width" => 640, "height" => 360}))
    @client = ActionDispatch::Integration::Session.new(Rails.application)
    @client.host! "lightek.test"
    Dashboard::StudioEditorsController.allow_forgery_protection = true
    @client.get "/test/csrf", headers: headers
    @token = JSON.parse(@client.response.body).fetch("csrf_token")
  end
  def document(kind = "video", scene = @scene) = Studio::Editors::Document.new(scene: scene, actor: @alice, kind: kind)
  def project_source
    {"mash" => {"width" => 640, "height" => 360, "quantize" => 30, "tracks" => [{"clips" => [{"frames" => 30, "containerId" => "com.moviemasher.container.text", "container" => {"string" => "Lightek launch", "intrinsic" => {"x" => 0, "y" => 0, "width" => 5000, "height" => 1000}}}]}]}, "definitions" => []}
  end
  def test_editor_source_reopens_and_stale_tab_cannot_overwrite_it
    source = project_source
    version = @scene.lock_version
    document.save!(document: source, lock_version: version)
    assert_equal @scene.lock_version, StudioScene.find(@scene.id).lock_version
    assert_equal "Lightek launch", document.load.dig("mash", "tracks", 0, "clips", 0, "container", "string")
    assert_raises(ActiveRecord::StaleObjectError) { document.save!(document: source, lock_version: version) }
    assert_equal "video", @scene.reload.settings["editor_kind"]
  end
  def test_editor_save_and_export_retry_recovers_after_queue_submission_fails
    document.save!(document: project_source, lock_version: @scene.lock_version)
    key = SecureRandom.uuid
    StudioEditorExportJob.stub(:perform_later, ->(*) { raise "Queue temporarily unavailable" }) do
      assert_raises(RuntimeError) { Studio::Editors::Export.start!(scene: @scene, actor: @alice, kind: "video", request_key: key) }
    end
    operation = @scene.studio_operations.where(capability: "studio.editor.export").sole
    assert_equal "pending", operation.status
    recovered = Studio::Editors::Export.start!(scene: @scene, actor: @alice, kind: "video", request_key: key)
    assert_equal operation.id, recovered.id
    assert_equal 1, @scene.studio_operations.where(capability: "studio.editor.export").count
  end
  def test_editor_rejects_foreign_media_and_photo_remote_fonts_and_prototype_data
    asset = StudioAsset.create!(owner: @bob, site: @other_site, kind: "video", name: "Private", request_key: SecureRandom.uuid, status: "uploaded")
    source = project_source; source["definitions"] = [{"id" => "lightek.media.#{asset.id}"}]
    assert_raises(ActiveRecord::RecordNotFound) { document.normalize(source) }
    source = project_source; source["mash"]["__proto__"] = {"url" => "file:///etc/passwd"}
    assert_raises(ArgumentError) { document.normalize(source) }
    photo = {"info" => {"width" => 640, "height" => 360}, "layers" => [], "data" => [], "user_fonts" => {"Custom" => "https://example.com/font.ttf"}}
    assert_raises(ArgumentError) { document("photo", @photo).normalize(photo) }
  end
  def test_editor_rejects_custom_network_sources_unsafe_filters_and_out_of_bounds_renders
    source = project_source
    source["mash"]["source"] = "http://127.0.0.1/secret"
    assert_raises(ArgumentError) { document.normalize(source) }
    source = project_source
    source["definitions"] = [{"id" => "remote-video", "type" => "video", "url" => "file:///etc/passwd"}]
    assert_raises(ArgumentError) { document.normalize(source) }
    source = project_source; source["mash"]["width"] = 100000
    assert_raises(ArgumentError) { document.normalize(source) }
    source = project_source; source["mash"]["tracks"][0]["clips"][0]["frames"] = 30 * 601
    assert_raises(ArgumentError) { document.normalize(source) }
  end
  def test_editor_real_movie_masher_export_creates_playable_mp4_and_library_item_once
    document.save!(document: project_source, lock_version: @scene.lock_version)
    key = SecureRandom.uuid
    operation = Studio::Editors::Export.start!(scene: @scene, actor: @alice, kind: "video", request_key: key)
    assert_equal operation.id, Studio::Editors::Export.start!(scene: @scene, actor: @alice, kind: "video", request_key: key).id
    StudioEditorExportJob.perform_now(operation.id)
    assert_equal "completed", operation.reload.status
    artifact = operation.artifacts.sole
    assert_equal "video/mp4", artifact.file.content_type
    assert artifact.file.blob.byte_size > 1000
    assert StudioAsset.find(operation.metadata.fetch("asset_id")).file.attached?
    StudioEditorExportJob.perform_now(operation.id)
    assert_equal 1, operation.artifacts.count
  end
  def test_editor_real_movie_masher_export_accepts_video_without_an_audio_track
    Dir.mktmpdir("silent-editor-") do |folder|
      file = File.join(folder, "silent.webm")
      Studio::MediaProcess.run!(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=blue:s=320x180:d=1:r=30", "-an", "-c:v", "libvpx", "-threads", "1", file])
      asset = StudioAsset.new(owner: @alice, site: @site, name: "Silent video", kind: "video", status: "uploaded", request_key: SecureRandom.uuid)
      asset.file.attach(io: File.open(file), filename: "silent.webm", content_type: "video/webm", identify: false)
      asset.save!
      source = {"mash" => {"width" => 640, "height" => 360, "quantize" => 30, "tracks" => [{"clips" => [{"frames" => 30, "contentId" => "lightek.media.#{asset.id}"}]}]}, "definitions" => [{"id" => "lightek.media.#{asset.id}", "width" => 320, "height" => 180, "duration" => 1, "audio" => true}]}
      document.save!(document: source, lock_version: @scene.lock_version)
      operation = Studio::Editors::Export.start!(scene: @scene, actor: @alice, kind: "video", request_key: SecureRandom.uuid)
      StudioEditorExportJob.perform_now(operation.id)
      assert_equal "completed", operation.reload.status
      assert_equal "video/mp4", operation.artifacts.sole.file.content_type
    end
  end
  def test_editor_http_creation_reopen_permissions_csrf_and_form_validation
    @client.get "/dashboard/studio/editors/photo/new?site_id=#{@site.id}", headers: headers.merge("Accept" => "text/html")
    assert_equal 200, @client.response.status
    @client.post "/dashboard/studio/editors/photo/?site_id=#{@site.id}", headers: headers.merge("X-CSRF-Token" => @token), params: {name: "Our poster", request_key: SecureRandom.uuid, format: "square"}
    assert_equal 303, @client.response.status
    destination = @client.response.location
    @client.get destination, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, @client.response.status
    assert_includes @client.response.body, "lightek-photo-editor"
    @client.get "/dashboard/studio/editors/video/#{@scene.id}?site_id=#{@other_site.id}", headers: headers
    assert_equal 404, @client.response.status
    @client.post "/dashboard/studio/editors/video/?site_id=#{@site.id}", headers: headers, params: {name: "CSRF", request_key: SecureRandom.uuid}
    assert_equal 422, @client.response.status
  end
end

# Browser acceptance talks to these real controllers through a stdio transport;
# only private host authentication is supplied by the fixture boundary.
if ENV["STUDIO_EDITOR_RPC"] == "1"
  Minitest::Runnable.runnables.clear
  fixture = StudioEditorsChecks.new("browser")
  fixture.setup
  client = fixture.instance_variable_get(:@client)
  actor = fixture.instance_variable_get(:@alice)
  $stdout.sync = true
  puts({ready: true, site_id: fixture.instance_variable_get(:@site).id, video_scene_id: fixture.instance_variable_get(:@scene).id, photo_scene_id: fixture.instance_variable_get(:@photo).id}.to_json)
  STDIN.each_line do |line|
    begin
      data = JSON.parse(line)
      if data["jobs"]
        StudioOperation.where(status: "pending", capability: "studio.editor.export").find_each { |operation| StudioEditorExportJob.perform_now(operation.id) }
        puts({jobs: true}.to_json)
        next
      end
      request_headers = data.fetch("headers", {}).merge("X-Pwa-Test-User" => actor.id.to_s, "HTTP_HOST" => data.fetch("headers", {}).fetch("host", "lightek.test"))
      client.process(data.fetch("method").downcase, data.fetch("path"), params: Base64.decode64(data.fetch("body", "")), headers: request_headers)
      puts({status: client.response.status, headers: client.response.headers.to_h, body: Base64.strict_encode64(client.response.body)}.to_json)
    rescue => error
      puts({error: "#{error.class}: #{error.message}", trace: error.backtrace.first(5)}.to_json)
    end
  end
  fixture.teardown
end
