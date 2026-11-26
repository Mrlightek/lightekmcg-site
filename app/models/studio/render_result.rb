require "securerandom"

module Studio
  class RenderResult < ApplicationRecord
    self.table_name = "studio_render_results"

    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :user
    belongs_to :operation_record, class_name: "Studio::OperationRecord", optional: true
    has_one_attached :output
    has_one_attached :source_project
    has_one_attached :editor_input
    has_many_attached :editor_assets

    validates :operation_id, format: {with: Operation::Thick::ID}
    validates :surface, inclusion: {in: Operation::Thick::SURFACES}
    validates :version, numericality: {only_integer: true, greater_than: 0}
    validates :status, inclusion: {in: %w[pending running completed failed]}

    validate :same_operation_site

    def completed? = status == "completed"
    def failed? = status == "failed"

    def terminal? = completed? || failed?

    def progress_cache_key = ["studio", "editor-render-progress", site_id, id]

    def video? = output.attached? && output.content_type == "video/mp4"

    def downloadable_output
      output if completed? && output.attached? && !legacy_project?
    end

    def downloadable_project
      return unless terminal?
      return source_project if source_project.attached?

      output if completed? && legacy_project?
    end

    def store_file!(attachment, path, extension:, content_type:, **attributes)
      key = SecureRandom.hex(24)
      filename = "#{operation_id.delete_prefix('studio.')}-v#{version}#{extension}"
      blob = File.open(path, "rb") do |io|
        ActiveStorage::Blob.create_and_upload!(key: key, io: io, filename: filename, content_type: content_type, identify: false)
      end
      update!(attachment => blob, **attributes)
    rescue StandardError
      (blob || ActiveStorage::Blob.find_by(key: key))&.purge
      raise
    end

    def fail_step!(error, phase: nil)
      detail = case phase
      when "render" then "The editable project was created, but the video render failed. #{error.message}"
      when "recipe" then "Recipe execution failed. #{error.message}"
      else error.message
      end
      update!(status: "failed", completed_at: Time.current, error_message: {
        step_index: error.step_index, command: error.command, engine: error.engine,
        reason: error.reason, stderr: error.stderr, detail: detail, phase: phase
      })
    end

    private

    def legacy_project? = output.attached? && output.filename.extension_without_delimiter == "ecproj"

    def same_operation_site
      errors.add(:operation_record, "must belong to this site") if operation_record && operation_record.site_id != site_id
    end
  end
end
