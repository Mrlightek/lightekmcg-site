require "tmpdir"

module Studio
  module MacroMaker
    class MotionRunJob < ApplicationJob
      queue_as :default

      DEFAULT_TIMEOUT = 600

      def perform(result_id, origin, parameters, inputs, asset_paths = [])
        result = RenderResult.find_by(id: result_id)
        return unless result && claim(result)

        phase = "recipe"
        deadline = monotonic_time + timeout
        adapters = Operation::EngineAdapter.configured
        operation = load_operation(result, origin, adapters)
        broadcast(result)
        Dir.mktmpdir("studio-macro-run-") do |directory|
          project = File.join(directory, "project.ecproj")
          video = File.join(directory, "output.mp4")
          if result.editor_input.attached?
            source = File.join(directory, "source.ecproj")
            assets = result.editor_assets.index_by { |attachment| attachment.filename.to_s }
            export = EffectCraftExport.load(result.editor_input.download)
            links = export.stage!(source, assets, asset_paths)
          end
          operation.run!(input: source, output: project, parameters: parameters, inputs: inputs, total_timeout: deadline - monotonic_time)
          editable_project = project
          if links&.any?
            editable_project = File.join(directory, "editable.ecproj")
            EffectCraftExport.load(File.read(project)).restore!(editable_project, links, directory)
          end
          result.store_file!(:source_project, editable_project, extension: ".ecproj", content_type: "application/octet-stream")
          phase = "render"
          broadcast(result, rendering: true)
          EffectCraftRenderer.render!(executable: adapters.fetch("effectcraft").executable,
            project: project, output: video, timeout: deadline - monotonic_time) do |percent|
            broadcast(result, rendering: true, percent: percent)
          end
          result.store_file!(:output, video, extension: ".mp4", content_type: "video/mp4",
            status: "completed", completed_at: Time.current)
        end
      rescue RecipeSession::StepError => error
        result.fail_step!(error, phase: phase)
      rescue StandardError => error
        raise unless result && phase

        Rails.logger.error("Studio motion run #{result.id} failed in #{phase}: #{error.class}")
        failure = RecipeSession::StepError.new(step_index: nil, command: phase == "render" ? "render" : "prepare",
          engine: "effectcraft", reason: :protocol_error, stderr: "",
          detail: phase == "render" ? "Studio could not store the rendered video." : "Studio could not create or store the project.")
        result.fail_step!(failure, phase: phase)
      ensure
        if phase && result
          begin
            result.editor_input.purge if result.editor_input.attached?
            result.editor_assets.purge if result.editor_assets.attached?
          ensure
            broadcast(result) if result.terminal?
          end
        end
      end

      private

      def claim(result)
        now = Time.current
        RenderResult.where(id: result.id, status: "pending").update_all(
          status: "running", started_at: now, updated_at: now) == 1 && result.reload
      end

      def load_operation(result, origin, adapters)
        operation = if origin == "tenant"
          record = OperationRecord.published.find_by!(id: result.operation_record_id, site_id: result.site_id,
            operation_id: result.operation_id, surface: result.surface, version: result.version)
          record.operation(engine_adapters: adapters)
        else
          OperationCatalog.find(result.site, result.operation_id, origin: :builtin,
            surface: result.surface, engine_adapters: adapters)
        end
        return operation if operation&.engine == "effectcraft" && operation.recipe.version == result.version

        raise ActiveRecord::RecordNotFound
      end

      def timeout
        value = Float(ENV.fetch("STUDIO_EFFECTCRAFT_RENDER_TIMEOUT_SECONDS", DEFAULT_TIMEOUT.to_s), exception: false)
        RecipeSession.valid_timeout?(value) ? value : DEFAULT_TIMEOUT
      end

      def monotonic_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def broadcast(result, rendering: false, percent: nil)
        cache_progress(result, rendering, percent)
        if result.terminal?
          Turbo::StreamsChannel.broadcast_render_to(result,
            partial: "studio/macro_maker/motion_run_finished", locals: {run: result})
        else
          Turbo::StreamsChannel.broadcast_replace_to(result, target: "macro_run_#{result.id}",
            partial: "studio/macro_maker/run_status",
            locals: {run: result, rendering: rendering, percent: percent})
        end
      rescue StandardError => error
        Rails.logger.warn("Studio motion run #{result.id} broadcast failed: #{error.class}")
      end
      def cache_progress(result, rendering, percent)
        if result.terminal?
          Rails.cache.delete(result.progress_cache_key)
        elsif rendering
          Rails.cache.write(result.progress_cache_key, {phase: "render", percent: percent}, expires_in: 2.minutes)
        end
      rescue StandardError => error
        Rails.logger.warn("Studio motion run #{result.id} progress cache failed: #{error.class}")
      end
    end
  end
end
