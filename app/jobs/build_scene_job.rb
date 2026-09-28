class BuildSceneJob < ApplicationJob
  queue_as :blender

  OUTPUTS = {
    "scene.blend" => "blend",
    "scene.glb" => "glb",
    "preview.png" => "preview",
    "manifest.json" => "manifest",
    "blender.log" => "log"
  }.freeze

  def perform(creation_job_id)
    creation_job = CreationJob.find(creation_job_id)
    creation_job.update!(status: "running", started_at: Time.current, error_message: nil)
    result = Blender::Runner.new(creation_job).call

    attach_outputs(creation_job, result.output_directory)
    creation_job.update!(status: "completed", completed_at: Time.current)
  rescue StandardError => error
    creation_job&.update(status: "failed", completed_at: Time.current, error_message: error.message.to_s.first(2_000))
    raise
  end

  private

  def attach_outputs(creation_job, directory)
    OUTPUTS.each do |filename, kind|
      path = directory.join(filename)
      next unless path.exist?

      artifact = creation_job.artifacts.create!(kind:, filename:)
      artifact.file.attach(io: File.open(path), filename:, content_type: content_type_for(filename))
    end
  end

  def content_type_for(filename)
    {
      ".png" => "image/png",
      ".json" => "application/json",
      ".glb" => "model/gltf-binary",
      ".blend" => "application/octet-stream",
      ".log" => "text/plain"
    }.fetch(File.extname(filename), "application/octet-stream")
  end
end

