# frozen_string_literal: true

require "open3"
require "json"

class AnimationPipelineJob < ApplicationJob
  queue_as :studio

  LOG_LIMIT = 64.kilobytes
  PIPELINE = Studio::Pipeline::CharacterAnimation

  def perform(operation_id, attempt)
    operation = StudioOperation.find_by(id: operation_id, capability: PIPELINE::CAPABILITY)
    return unless operation

    operation.with_lock do
      return unless current_attempt?(operation, "pending", attempt)
      operation.update!(status: "running", started_at: Time.current)
    end
    claimed = true
    uploads = {}
    project = operation.studio_project
    Studio::Pipeline::Access.new(project.owner, project.site)
    mode = operation.metadata.fetch("mode")
    credential_input = mode == "full" ? JSON.generate(Studio::Pipeline::MixamoCredentials.checkout(project.owner)) : nil
    stdout = stderr = ""
    status = nil
    Studio::MediaProcess.temporary_directory("character-animation-") do |directory|
      if mode == "render-only"
        animated = PIPELINE.file(operation, "package")
        raise "The downloaded animated FBX is unavailable" unless animated

        File.open(File.join(directory, "animated.fbx"), "wb") do |file|
          animated.download { |chunk| file.write(chunk) }
        end
      end
      settings = operation.manifest
      env = {
        "OUTPUT_DIR" => directory, "GENDER" => settings.fetch("gender"), "HEIGHT" => settings.fetch("height"),
        "MUSCLE" => settings.fetch("muscle"), "MIXAMO_ANIMATION" => settings.fetch("animation"),
        "MIXAMO_ANIMATION_ID" => settings.fetch("animation_id"), "FRAMES" => settings.fetch("frames"),
        "RENDER_RESOLUTION" => settings.fetch("resolution")
      }.transform_values(&:to_s)
      stdout, stderr, status = Open3.capture3(env, "bash", Rails.root.join("script/run_pipeline.sh").to_s,
        "--#{mode}", chdir: Rails.root.to_s, binmode: true, stdin_data: credential_input)

      animated_path = File.join(directory, "animated.fbx")
      if mode == "full" && status.exitstatus != 42 && File.size?(animated_path)
        uploads["package"] = upload(animated_path, "animated.fbx", "application/octet-stream")
      end
      if status.success?
        uploads["video"] = upload(File.join(directory, "preview.mp4"), "character-#{operation.id}-#{attempt}.mp4", "video/mp4")
      end
    end

    if status.exitstatus == 42 && mode == "full"
      finish(operation, attempt, "awaiting_manual_login", stdout, stderr, status.exitstatus, uploads,
        "The studio operator needs to reconnect the animation service.")
    elsif status.success?
      finish(operation, attempt, "completed", stdout, stderr, status.exitstatus, uploads)
    else
      code = status.exitstatus || "signal #{status.termsig}"
      finish(operation, attempt, "failed", stdout, stderr, status.exitstatus, uploads,
        "Character pipeline exited with #{code}. See the job logs.")
    end
  rescue StandardError => error
    raise unless claimed
    Rails.logger.error("Animation pipeline #{operation_id}: #{error.class}: #{error.message}")
    failure_log = [stderr, "Studio worker: #{error.class}: #{error.message}"].compact.join("\n")
    # A Blender or preview failure can still leave a reusable FBX.
    finish(operation, attempt, "failed", stdout, failure_log, status&.exitstatus,
      uploads.except("video"), "The Studio worker could not finish this attempt. See the job logs.")
  ensure
    credential_input&.clear
    uploads&.each_value { |blob| blob.purge_later unless blob.attachments.exists? }
  end

  private

  def current_attempt?(operation, state, attempt)
    operation.status == state && operation.metadata["attempt"] == attempt
  end

  def upload(path, filename, content_type)
    raise "Pipeline output #{filename} is missing or empty" unless File.size?(path)
    File.open(path, "rb") do |file|
      ActiveStorage::Blob.create_and_upload!(io: file, filename: filename, content_type: content_type, identify: false)
    end
  end

  def finish(operation, attempt, state, stdout, stderr, exit_code, uploads, error = nil)
    operation.with_lock do
      return unless current_attempt?(operation, "running", attempt)

      uploads.each do |kind, blob|
        artifact = operation.artifacts.create!(kind: kind, filename: blob.filename.to_s,
          metadata: {"attempt" => attempt})
        artifact.file.attach(blob)
      end
      operation.update!(status: state, error_message: error, completed_at: Time.current,
        metadata: operation.metadata.merge("stdout" => log_tail(stdout), "stderr" => log_tail(stderr),
          "exit_code" => exit_code, "logged_attempt" => attempt))
    end
  end

  def log_tail(value)
    bytes = value.to_s.b
    bytes = "[Earlier output omitted]\n".b + bytes.byteslice(-LOG_LIMIT, LOG_LIMIT) if bytes.bytesize > LOG_LIMIT
    bytes.force_encoding(Encoding::UTF_8).scrub.delete("\u0000")
  end
end
