require "tmpdir"

module Studio
  module MacroMaker
    class Runner
      TOTAL_TIMEOUT = 9
      MAX_UPLOAD = 20 * 1024 * 1024
      IMAGE_EXTENSIONS = {"image/png" => ".png", "image/jpeg" => ".jpg", "image/webp" => ".webp"}.freeze

      def initialize(site:, user:, operation:, requirements:)
        @site = site
        @user = user
        @operation = operation
        @requirements = requirements
      end

      def call(upload:, parameters:, inputs:, context: {}, editor_export: false, asset_paths: [], assets: [])
        missing = @requirements.reject { |flag| context[flag.to_s] == true }
        unless missing.empty?
          raise ArgumentError, "This operation requires live document context: #{missing.map { |flag| flag.to_s.humanize.downcase }.join(', ')}"
        end

        @operation.validate_run_bindings!(parameters: parameters, inputs: inputs)
        extension = editor_export ? EditorExport.extension(upload, @operation.engine, asset_paths: asset_paths, assets: assets) : upload_extension(upload)
        motion = @operation.engine == "effectcraft"
        result = start_result(upload, motion: motion)
        if motion
          if editor_export
            upload.tempfile.rewind
            result.editor_input.attach(io: upload.tempfile, filename: "source.ecproj",
              content_type: "application/octet-stream", identify: false)
          end
          if assets.any?
            result.editor_assets.attach(assets.each_with_index.map do |asset, index|
              {io: asset.tempfile, filename: "asset-#{index}", content_type: "application/octet-stream", identify: false}
            end)
          end
          job = MotionRunJob.perform_later(result.id, @operation.origin.to_s, parameters, inputs, asset_paths)
          raise "Could not enqueue the motion run" unless job

          return result
        end

        Dir.mktmpdir("studio-macro-run-") do |directory|
          source = copy_input(upload, directory, extension) if extension
          output = File.join(directory, "output.png")
          @operation.run!(input: source, output: output, parameters: parameters, inputs: inputs, total_timeout: TOTAL_TIMEOUT)
          result.store_file!(:output, output, extension: ".png", content_type: "image/png",
            status: "completed", completed_at: Time.current)
        end
        result
      rescue RecipeSession::StepError => error
        result.fail_step!(error)
        result
      rescue Composition::Invalid, ArgumentError => error
        raise unless result

        purge_editor_input(result) if motion
        errors = error.respond_to?(:errors) ? error.errors : [
          {step_index: nil, step_operation_id: @operation.id, kind: :invalid_binding, detail: error.message}
        ]
        result.update!(status: "failed", completed_at: Time.current, error_message: {errors: errors})
        result
      rescue StandardError => error
        raise unless result

        purge_editor_input(result) if motion
        Rails.logger.error("Studio macro run #{result.id} failed: #{error.class}")
        result.update!(status: "failed", completed_at: Time.current, error_message: {
          errors: [{step_index: nil, step_operation_id: @operation.id, kind: :execution_error,
            detail: motion ? "Studio could not queue the motion run." : "Studio could not prepare the input or store the output."}]
        })
        result
      end

      def self.requires_input?(operation) = operation.engine == "photocraft"

      private

      def purge_editor_input(result)
        result.editor_input.purge if result.editor_input.attached?
        result.editor_assets.purge if result.editor_assets.attached?
      end

      def upload_extension(upload)
        unless self.class.requires_input?(@operation)
          raise ArgumentError, "EffectCraft starts a new project and does not accept an upload" if upload

          return nil
        end
        unless upload.is_a?(ActionDispatch::Http::UploadedFile) && upload.size.positive?
          raise ArgumentError, "Upload an input image"
        end
        raise ArgumentError, "Input images must be 20 MiB or smaller" if upload.size > MAX_UPLOAD

        IMAGE_EXTENSIONS.fetch(Marcel::MimeType.for(upload.tempfile)) do
          raise ArgumentError, "Upload a PNG, JPEG, or WebP image"
        end
      end

      def copy_input(upload, directory, extension)
        path = File.join(directory, "input#{extension}")
        upload.tempfile.rewind
        IO.copy_stream(upload.tempfile, path)
        path
      end

      def start_result(upload, motion:)
        record = if @operation.origin == :tenant
          OperationRecord.published.find_by!(site: @site, operation_id: @operation.id, surface: @operation.surface,
            version: @operation.recipe.version)
        end

        RenderResult.create!(site: @site, user: @user, operation_record: record, operation_id: @operation.id,
          version: @operation.recipe.version, surface: @operation.surface.to_s,
          input_filename: (ActiveStorage::Filename.new(upload.original_filename).sanitized if upload),
          status: motion ? "pending" : "running", started_at: (Time.current unless motion))
      end
    end
  end
end
