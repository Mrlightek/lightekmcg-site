# frozen_string_literal: true

require_relative "pwa_http_checks"
require "minitest/mock"
require File.join(ROOT, "app/services/studio/broadcasting/access")
%w[scene_spec manifest].each { |name| require File.join(ROOT, "app/services/studio/animation", name) }
%w[base assets scenes renders].each { |name| require File.join(ROOT, "app/controllers/studio/animation", "#{name}_controller") }
require File.join(ROOT, "app/jobs/studio_scene_render_job")
require File.join(ROOT, "app/jobs/studio_scene_render_sweep_job")
require File.join(ROOT, "app/jobs/studio_animation_preview_job")

Studio::Animation::BaseController.prepend_view_path(File.join(ROOT, "app/views"))
Rails.application.routes.append do
  scope "/studio/pipeline" do
    get "/", to: "studio/animation/scenes#index", as: :studio_pipeline
  end
end
Rails.application.reload_routes!

class StudioSceneAnimationChecks < PwaHttpIntegrationTest
  PwaHttpIntegrationTest.instance_methods(false).grep(/^test_/).each { |name| undef_method(name) }

  def setup
    super
    @site.update!(tenant: @alice)
    @client = session_for
    @client.get "/test/csrf", headers: headers
    @csrf_token = body(@client).fetch("csrf_token")
  end

  def test_animation_assets_and_scenes_have_owner_only_crud_including_for_administrators
    file = Rack::Test::UploadedFile.new(StringIO.new("artwork fixture"), "image/png", original_filename: "actor.png")
    @client.post assets_url, params: { asset: { name: "Actor", animation_role: "character", dimension_mode: "2d", file: file } }, headers: headers
    assert_equal 201, @client.response.status, @client.response.body
    asset = body(@client)
    @client.patch "#{assets_url}/#{asset['id']}", params: { asset: { name: "Renamed actor" } }, headers: headers, as: :json
    assert_equal "Renamed actor", body(@client).fetch("name")
    @client.get asset.fetch("file_url"), headers: headers.merge("Range" => "bytes=0-6")
    assert_equal 206, @client.response.status
    assert_equal "artwork", @client.response.body

    scene = create_scene(layers: [{ asset_id: asset["id"], dimension_mode: "2d" }])
    scene_url = "#{scenes_url}/#{scene['id']}"
    @client.patch scene_url, params: { scene: { name: "Updated scene" } }, headers: headers, as: :json
    assert_equal "Updated scene", body(@client).fetch("name")
    @client.get scene_url, headers: headers.merge("Accept" => "text/html")
    assert_equal 200, @client.response.status
    assert_includes @client.response.body, "Render MP4"

    @bob.update!(role: "super_admin")
    legacy_access = Studio::PwaAccess.new("user_id" => @bob.id, "site_id" => @site.id)
    refute legacy_access.projects.exists?(scene["studio_project_id"])
    refute StudioAsset.for_actor(legacy_access).exists?(asset["id"])
    @client.get "/api/lightek/pwa/assets/#{asset['id']}/original", headers: headers(@bob)
    assert_equal 404, @client.response.status
    @client.get scene_url, headers: headers(@bob)
    assert_equal 404, @client.response.status
    @client.delete "#{assets_url}/#{asset['id']}", headers: headers(@bob)
    assert_equal 404, @client.response.status
    @client.delete scene_url, headers: headers
    assert_equal 204, @client.response.status
    @client.delete "#{assets_url}/#{asset['id']}", headers: headers
    assert_equal 204, @client.response.status
  end

  def test_animation_saves_curves_and_rejects_a_stale_editor
    scene = create_scene
    scene_url = "#{scenes_url}/#{scene['id']}"
    version = scene.fetch("lock_version")
    camera = { keyframes: [{ time_ms: 750, lens: 60, interpolation: "BEZIER" }] }
    @client.patch scene_url, params: { scene: { lock_version: version, scene_spec: { camera: camera } } }, headers: headers, as: :json
    assert_equal 200, @client.response.status
    assert_equal "BEZIER", body(@client).dig("scene_spec", "camera", "keyframes", 0, "interpolation")
    @client.patch scene_url, params: { scene: { lock_version: version, name: "Stale" } }, headers: headers, as: :json
    assert_equal 422, @client.response.status
    assert_match(/changed in another tab/, body(@client).fetch("error"))
  end

  def test_animation_model_preview_is_private_and_is_reset_by_a_replacement
    file = Rack::Test::UploadedFile.new(StringIO.new("model fixture"), "application/octet-stream", original_filename: "actor.blend")
    @client.post assets_url, params: { asset: { name: "Native model", animation_role: "character", dimension_mode: "3d", file: file } }, headers: headers
    assert_equal 201, @client.response.status
    record = body(@client)
    asset = StudioAsset.find(record.fetch("id"))
    url = record.fetch("preview_request_url")
    options = { source_revision: record.fetch("source_revision"), fps: 24, action_name: "Walk", pose_frame: 12 }
    @client.get url, params: options, headers: headers
    assert_equal "missing", body(@client).fetch("preview_status")
    @client.post url, params: options, headers: headers, as: :json
    assert_equal 202, @client.response.status
    assert_equal "queued", body(@client).fetch("preview_status")
    preview = asset.studio_animation_previews.sole
    @client.post url, params: options, headers: headers, as: :json
    assert_equal 1, asset.studio_animation_previews.count
    assert_equal({ "blob_id" => asset.file.blob.id, "fps" => 24, "starter" => false,
      "action" => "Walk", "pose_frame" => 12 }, preview.settings)
    [{ fps: 30 }, { action_name: "Idle" }, { pose_frame: 13 }].each do |variant|
      @client.post url, params: options.merge(variant), headers: headers, as: :json
      assert_equal 202, @client.response.status
    end
    assert_equal 4, asset.studio_animation_previews.distinct.count(:variant_digest)

    preview.file.attach(io: StringIO.new("proxy"), filename: "proxy.glb", content_type: "model/gltf-binary", identify: false)
    preview.update!(status: "ready")
    @client.get url, params: options, headers: headers
    assert_equal ["ready", "static", 12, []], body(@client).values_at("preview_status", "preview_kind", "evaluated_frame", "clips")
    download = body(@client).fetch("preview_url")
    @client.get download, headers: headers
    assert_equal "proxy", @client.response.body
    @bob.update!(role: "super_admin")
    @client.get download, headers: headers(@bob)
    assert_equal 404, @client.response.status

    asset.file.attach(io: StringIO.new("replacement"), filename: "revised.blend", identify: false)
    @client.get download, headers: headers
    assert_equal 404, @client.response.status
    @client.post url, params: options, headers: headers, as: :json
    assert_equal 422, @client.response.status
    @client.get url, params: options.except(:source_revision), headers: headers
    assert_equal "missing", body(@client).fetch("preview_status")
  end

  def test_animation_preview_job_passes_pose_settings_and_publishes_the_generated_blob
    asset = make_asset(owner: @alice, role: nil, extension: "blend")
    settings = StudioAnimationPreview.settings_for(asset, { fps: 30, action_name: "Walk", pose_frame: 0 })
    preview = asset.studio_animation_previews.create!(variant_digest: StudioAnimationPreview.key_for(settings),
      settings: settings, attempt_token: SecureRandom.uuid)
    container = lambda do |_args, root:, **_options|
      manifest = JSON.parse(File.read(File.join(root, "preview.json")))
      assert_equal [1, 30, "Walk", 0, true], manifest.values_at("version", "fps", "action", "pose_frame", "starter")
      assert_equal "fixture", File.binread(File.join(root, manifest.fetch("source")))
      File.binwrite(File.join(root, "preview.glb"), "Blender pose fixture")
      ["blender"]
    end
    Rails.stub(:root, Pathname(ROOT)) do
      Studio::MediaProcess.stub(:container, container) do
        Studio::MediaProcess.stub(:run!, nil) do
          StudioAnimationPreviewJob.perform_now(preview.id, preview.attempt_token)
        end
      end
    end
    assert_equal "ready", preview.reload.status
    assert_equal "Blender pose fixture", preview.file.download
  end

  def test_animation_render_pins_inputs_accepts_starters_and_serves_only_to_owner
    starter = make_asset(owner: @alice, role: nil, extension: "blend")
    artwork = make_asset(owner: @alice, role: "viseme", extension: "png")
    character = make_asset(owner: @alice, role: "character", extension: "webp")
    foreign = make_asset(owner: @bob, role: "character", extension: "webp")
    audio = make_asset(owner: @alice, role: "audio", extension: "wav")
    scene = create_scene(aspect_ratio: "9:16", fps: 24, duration_ms: 1020, audio_asset_id: audio.id, layers: [
      { asset_id: character.id, dimension_mode: "2_5d", z_depth: 1, mouth: {
        variants: { rest: artwork.id }, cues: [{ start_ms: 200, end_ms: 500, viseme: "A" }]
      } },
      { asset_id: starter.id, dimension_mode: "3d" }
    ])
    scene_url = "#{scenes_url}/#{scene['id']}"
    submit_render(scene_url, scene.fetch("lock_version"))
    assert_equal 202, @client.response.status, @client.response.body
    item = StudioSceneRender.find(body(@client).fetch("id"))
    assert_equal "queued", item.status
    assert_equal [720, 1280, 25], item.manifest.values_at("width", "height", "frame_count")
    assert_equal [artwork.file.blob.id, character.file.blob.id, starter.native.blob.id, audio.file.blob.id].sort,
      item.inputs.blobs.ids.sort
    assert_equal "inputs/#{artwork.file.blob.id}.png", item.manifest.dig("layers", 0, "mouth", "variants", "X")
    old_blob = character.file.blob
    character.file.attach(io: StringIO.new("changed"), filename: "revised.webp", identify: false)
    assert_includes item.inputs.blobs, old_blob

    submit_render(scene_url, scene.fetch("lock_version"))
    assert_equal 409, @client.response.status
    @client.delete scene_url, headers: headers
    assert_equal 422, @client.response.status
    assert StudioScene.exists?(scene["id"])

    phases = []
    fake_runner = lambda do |args, root, **options|
      phases << item.reload.status
      if args.first == "blender"
        File.write(root.join("progress"), "20")
        options.fetch(:on_tick).call
        assert_operator item.reload.progress, :>, 5
      else
        File.write(root.join("scene.mp4"), "video bytes")
      end
    end
    job = StudioSceneRenderJob.new
    Rails.stub(:root, Pathname(ROOT)) do
      job.stub(:run, fake_runner) { job.perform(item.id) }
    end
    assert_equal %w[rendering encoding], phases
    assert_equal ["completed", 100], item.reload.values_at(:status, :progress)
    @client.get "#{scene_url}/renders/#{item.id}", headers: headers
    result = body(@client)
    @client.get result.fetch("video_url"), headers: headers.merge("Range" => "bytes=0-4")
    assert_equal 206, @client.response.status
    assert_equal "video", @client.response.body
    @client.get result.fetch("download_url"), headers: headers(@bob)
    assert_equal 404, @client.response.status

    @client.patch scene_url, params: { scene: { scene_spec: { layers: [{ asset_id: foreign.id, dimension_mode: "2d" }] } } }, headers: headers, as: :json
    assert_equal 200, @client.response.status
    submit_render(scene_url, body(@client).fetch("lock_version"))
    assert_equal 422, @client.response.status
    assert_match(/unavailable/, body(@client).fetch("error"))
  end

  def test_animation_render_submission_deduplicates_and_rejects_stale_scene_revisions
    scene, url = renderable_scene
    revision = scene.fetch("lock_version")
    request_id = SecureRandom.uuid
    jobs_before = ActiveJob::Base.queue_adapter.enqueued_jobs.size
    submit_render(url, revision, request_id: request_id)
    assert_equal 202, @client.response.status
    id = body(@client).fetch("id")
    render = StudioSceneRender.find(id)
    render.with_lock { render.mark_failed!("Simulated failure") }

    @client.patch url, params: { scene: { name: "Edited elsewhere", lock_version: revision } }, headers: headers, as: :json
    assert_equal 200, @client.response.status
    submit_render(url, revision, request_id: request_id)
    assert_equal 200, @client.response.status
    assert_equal id, body(@client).fetch("id")
    submit_render(url, revision)
    assert_equal 409, @client.response.status
    assert_includes body(@client).fetch("error"), "changed since you saved"
    assert_equal [id], render.studio_scene.studio_scene_renders.ids
    queued = ActiveJob::Base.queue_adapter.enqueued_jobs.drop(jobs_before).count { |job| job[:job] == StudioSceneRenderJob && job[:args] == [id] }
    assert_equal 1, queued
  end

  def test_animation_render_sweeper_expires_unclaimed_and_running_attempts
    scene, url = renderable_scene
    submit_render(url, scene.fetch("lock_version"))
    first = StudioSceneRender.find(body(@client).fetch("id"))
    first.update_columns(created_at: 31.minutes.ago)
    StudioSceneRenderSweepJob.perform_now
    assert_equal ["failed", "queued"], first.reload.values_at(:status, :failed_phase)
    refute first.claim!

    submit_render(url, scene.fetch("lock_version"))
    second = StudioSceneRender.find(body(@client).fetch("id"))
    token = second.claim!
    assert token.present?
    refute second.claim!
    assert_raises(StudioSceneRender::ClaimLost) { second.advance_claim!("wrong", "preparing", status: "rendering") }
    assert_raises(StudioSceneRender::ClaimLost) { second.advance_claim!(token, "rendering", status: "encoding") }
    second.update_columns(lease_expires_at: 1.second.ago)
    assert_raises(StudioSceneRender::ClaimLost) { second.advance_claim!(token, "preparing", status: "rendering") }
    StudioSceneRenderSweepJob.perform_now
    assert_equal ["failed", "preparing", nil], second.reload.values_at(:status, :failed_phase, :claim_token)
  end

  def test_animation_render_retries_original_inputs_and_rejects_late_worker_output
    scene, url = renderable_scene
    submit_render(url, scene.fetch("lock_version"))
    original = StudioSceneRender.find(body(@client).fetch("id"))
    runner = lambda do |args, root, **_options|
      if args.first == "python3"
        original.update_columns(lease_expires_at: 1.second.ago)
        StudioSceneRenderSweepJob.perform_now
        File.write(root.join("scene.mp4"), "late video bytes")
      end
    end
    job = StudioSceneRenderJob.new
    Rails.stub(:root, Pathname(ROOT)) do
      job.stub(:run, runner) { job.perform(original.id) }
    end
    assert_equal ["failed", "encoding"], original.reload.values_at(:status, :failed_phase)
    refute original.video.attached?
    @client.get "#{url}/renders/#{original.id}", headers: headers.merge("Accept" => "text/html")
    assert_includes @client.response.body, "Retry this render"
    assert_includes @client.response.body, "Failed during encoding"
    @client.get "#{url}/renders/#{original.id}", headers: headers
    retry_url = body(@client).fetch("retry_url")

    @client.patch url, params: { scene: { scene_spec: { layers: [] } } }, headers: headers, as: :json
    request_id = SecureRandom.uuid
    @client.post retry_url, params: { request_id: request_id }, headers: headers, as: :json
    assert_equal 202, @client.response.status
    retry_id = body(@client).fetch("id")
    attempt = StudioSceneRender.find(retry_id)
    assert_equal original.id, attempt.retry_of_id
    assert_equal original.manifest, attempt.manifest
    assert_equal original.inputs.blobs.ids, attempt.inputs.blobs.ids
    @client.post retry_url, params: { request_id: request_id }, headers: headers, as: :json
    assert_equal 200, @client.response.status
    assert_equal retry_id, body(@client).fetch("id")
    @client.post retry_url, params: { request_id: SecureRandom.uuid }, headers: headers(@bob), as: :json
    assert_equal 404, @client.response.status
  end

  def test_animation_render_purges_a_blob_when_its_claim_expires_mid_upload
    scene, url = renderable_scene
    submit_render(url, scene.fetch("lock_version"))
    render = StudioSceneRender.find(body(@client).fetch("id"))
    runner = lambda do |args, root, **_options|
      File.write(root.join("scene.mp4"), "video bytes") if args.first == "python3"
    end
    builder = ActiveStorage::Blob.method(:build_after_unfurling)
    late_blob = nil
    build = lambda do |**options|
      late_blob = builder.call(**options)
      original_upload = late_blob.method(:upload_without_unfurling)
      late_blob.define_singleton_method(:upload_without_unfurling) do |file|
        original_upload.call(file)
        render.update_columns(lease_expires_at: 1.second.ago)
        StudioSceneRenderSweepJob.perform_now
      end
      late_blob
    end
    job = StudioSceneRenderJob.new
    jobs_before = ActiveJob::Base.queue_adapter.enqueued_jobs.size
    Rails.stub(:root, Pathname(ROOT)) do
      job.stub(:run, runner) do
        ActiveStorage::Blob.stub(:build_after_unfurling, build) { job.perform(render.id) }
      end
    end
    assert_equal ["failed", "encoding"], render.reload.values_at(:status, :failed_phase)
    refute render.video.attached?
    assert late_blob.present?
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.drop(jobs_before).any? { |entry| entry[:job] == ActiveStorage::PurgeJob }
  end

  def test_animation_rejects_overlapping_cues_and_client_supplied_paths
    scene = create_scene
    scene_url = "#{scenes_url}/#{scene['id']}"
    [{ layers: [{ asset_id: 1, dimension_mode: "2d", source: "/etc/passwd" }] },
      { layers: [{ asset_id: 1, dimension_mode: "2d", mouth: { variants: { X: 2 }, cues: [
        { start_ms: 0, end_ms: 100, viseme: "A" }, { start_ms: 90, end_ms: 200, viseme: "B" }
      ] } }] }].each do |spec|
      @client.patch scene_url, params: { scene: { scene_spec: spec } }, headers: headers, as: :json
      assert_equal 422, @client.response.status
    end
    assert_empty StudioScene.find(scene["id"]).scene_spec.fetch("layers")
  end

  private

  def headers(user = @alice) = super.merge("X-CSRF-Token" => @csrf_token.to_s)

  def scenes_url = "/studio/animation/scenes"
  def assets_url = "/studio/animation/assets"

  def renderable_scene
    asset = make_asset(owner: @alice, role: "character", extension: "webp")
    scene = create_scene(layers: [{ asset_id: asset.id, dimension_mode: "2d" }])
    [scene, "#{scenes_url}/#{scene.fetch('id')}"]
  end

  def submit_render(url, revision, request_id: SecureRandom.uuid)
    @client.post "#{url}/renders", params: { lock_version: revision, request_id: request_id }, headers: headers, as: :json
  end

  def create_scene(**spec)
    @client.post scenes_url, params: { scene: { name: "Short", scene_spec: spec } }, headers: headers, as: :json
    assert_equal 201, @client.response.status, @client.response.body
    body(@client)
  end

  def make_asset(owner:, role:, extension:)
    kind = { "blend" => "blend", "wav" => "audio" }.fetch(extension, "image")
    asset = StudioAsset.new(owner: owner, site: @site, name: "Fixture", kind: kind, status: "ready",
      request_key: SecureRandom.uuid, animation_role: role,
      dimension_mode: ("2d" if role && role != "audio"), metadata: role ? {} : { "starter_cast" => {} })
    (role ? asset.file : asset.native).attach(io: StringIO.new("fixture"), filename: "asset.#{extension}", identify: false)
    asset.save!
    asset
  end
end
