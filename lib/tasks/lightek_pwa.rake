# frozen_string_literal: true
require "tmpdir"
require "stringio"
namespace :lightek_pwa do
  desc "Verify deployed PWA infrastructure and execute media-worker smoke renders (no payment or publication)"
  task verify_infrastructure: :environment do
    require "sidekiq/api"
    results = []
    check = lambda do |name, &block|
      block.call
      results << { check: name, status: "passed" }
    rescue StandardError => error
      # Credentials and provider responses must never enter verification output.
      results << { check: name, status: "failed", error_class: error.class.name }
    end
    check.call("PostgreSQL and migrations") do
      raise "PostgreSQL required" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      ActiveRecord::Migration.check_all_pending!
      ActiveRecord::Base.connection.select_value("SELECT 1")
    end
    check.call("Configured site host") do
      LightekPwa::SiteContext.resolve(ENV.fetch("LIGHTEK_VERIFY_HOST"))
    end
    check.call("PWA capabilities") do
      expected = Studio::Workers::Workspace::ACTIONS.map { |action| "studio.workspace.#{action.tr('_', '.')}" } +
        LightekCommunity::Workers::Pwa::ACTIONS.map { |action| "community.#{action.delete_prefix('community_').tr('_', '.')}" }
      raise "Missing capabilities" unless (expected - NevaehCapability.where(enabled: true).pluck(:slug)).empty?
    end
    check.call("Redis and active job consumers") do
      raise "Redis unavailable" unless Sidekiq.redis { |redis| redis.call("PING") } == "PONG"
      queues = Sidekiq::ProcessSet.new.flat_map { |process| Array(process["queues"]) }.uniq
      raise "Required queues have no consumers" unless (%w[default studio] - queues).empty?
    end
    check.call("Active Storage round trip") do
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("lightek-verification"), filename: "verification.txt", content_type: "text/plain", identify: false)
      raise "Storage mismatch" unless blob.download == "lightek-verification"
    ensure
      blob&.purge
    end
    check.call("Production pricing") do
      %w[build_scene edit_media].each { |kind| Studio::Billing::Pricing.principal_cents_for(kind) }
    end
    check.call("Server live encoder") do
      raise "FFmpeg missing" unless Studio::Live::Encoder.available?
      encoders = Studio::MediaProcess.run!([ENV.fetch("LIGHTEK_FFMPEG", "ffmpeg"), "-hide_banner", "-encoders"])
      raise "H264/AAC unavailable" unless encoders.include?("libx264") && encoders.match?(/\baac\b/)
    end
    check.call("Isolated production media workers") do
      Dir.mktmpdir("lightek-verification-") do |root|
        media_image = ENV.fetch("STUDIO_MEDIA_WORKER_IMAGE")
        asset_image = ENV.fetch("STUDIO_ASSET_WORKER_IMAGE")
        encode = ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=black:s=128x128:d=0.3", "-c:v", "libx264", "-threads", "1", "/work/master.mp4"]
        Studio::MediaProcess.run!(Studio::MediaProcess.container(encode, root: root, image: media_image))
        raise "Video encoding failed" unless File.size?(File.join(root, "master.mp4"))
        fixture = ["blender", "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python-expr", "import bpy; bpy.ops.wm.save_as_mainfile(filepath='/work/source.blend')"]
        Studio::MediaProcess.run!(Studio::MediaProcess.container(fixture, root: root, image: asset_image), timeout: 120)
        FileUtils.cp(Rails.root.join("blender/import_asset.py"), File.join(root, "import_asset.py"))
        convert = ["blender", "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python", "/work/import_asset.py", "--", "/work/source.blend", "/work", "blend"]
        Studio::MediaProcess.run!(Studio::MediaProcess.container(convert, root: root, image: asset_image), timeout: 240)
        raise "Model conversion failed" unless %w[asset.glb preview.png asset.json].all? { |name| File.size?(File.join(root, name)) }
      end
    end
    puts JSON.pretty_generate(environment: Rails.env, checked_at: Time.current.iso8601, checks: results,
      acceptance_status: "Authenticated browser, Stripe callback and destination delivery checks are separate and still required.")
    abort "Infrastructure verification failed; inspect the named checks on the application host." if results.any? { |result| result[:status] == "failed" }
  end
end
