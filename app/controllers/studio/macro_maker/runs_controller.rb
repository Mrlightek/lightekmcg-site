module Studio
  module MacroMaker
    class RunsController < WorkspaceController
      include StudioBlobStreaming

      before_action :authorize_editor_access, only: :apply
      before_action :load_operation, only: %i[new create apply]

      def new
        @recent_runs = recent_runs
        render "studio/macro_maker/run"
      end

      def create
        body = request.request_parameters
        runner = Runner.new(site: @site, user: @user, operation: @operation, requirements: @requirements)
        @result = runner.call(upload: body["input_file"], parameters: bindings(body, "parameters"), inputs: bindings(body, "inputs"))
        render_result
      rescue ArgumentError, JSON::ParserError => error
        invalid_run(error)
      end

      def apply
        body = request.request_parameters
        raise ArgumentError, "The editor does not match this operation" unless body["editor"] == @operation.engine

        context = bindings(body, "context")
        unless context.all? { |key, value| Operation::CommandMetadata::REQUIREMENTS.include?(key) && [true, false].include?(value) }
          raise ArgumentError, "Context must contain recognized boolean flags"
        end
        missing = @requirements.reject { |flag| context[flag.to_s] == true }
        if missing.any?
          return invalid_run(ArgumentError.new("This operation requires #{missing.map { |flag| flag.to_s.humanize.downcase }.to_sentence}"),
            kind: :missing_context, missing_context: missing)
        end

        asset_paths = JSON.parse(body.fetch("asset_paths", "[]"))
        assets = body.fetch("assets", [])
        if @operation.engine != "effectcraft" && (asset_paths != [] || assets != [])
          raise ArgumentError, "EffectCraft assets require an EffectCraft operation"
        end
        runner = Runner.new(site: @site, user: @user, operation: @operation, requirements: @requirements)
        @result = runner.call(upload: body["input_file"], parameters: bindings(body, "parameters"),
          inputs: bindings(body, "inputs"), context: context, editor_export: true, asset_paths: asset_paths, assets: assets)
        render json: result_payload(@result), status: result_status
      rescue EffectCraftExport::MissingAssets => error
        invalid_run(error, kind: :missing_assets, missing_assets: error.paths)
      rescue ArgumentError, JSON::ParserError, TypeError => error
        invalid_run(error)
      end

      def status
        @result = owned_results.find(params.fetch(:id))
        if request.format.json?
          render json: result_payload(@result)
        elsif @result.terminal?
          render partial: "studio/macro_maker/motion_run_finished", locals: {run: @result},
            formats: [:turbo_stream], content_type: Mime[:turbo_stream].to_s
        else
          head :no_content
        end
      end

      def download
        result = owned_results.find(params.fetch(:id))
        attachment = case params[:file]
        when nil, "output" then result.downloadable_output
        when "project" then result.downloadable_project
        end
        raise ActiveRecord::RecordNotFound unless attachment

        disposition = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: attachment.filename.to_s)
        response.headers["X-Content-Type-Options"] = "nosniff"
        stream_blob(attachment.blob, disposition: disposition)
      end

      private

      def load_operation
        id = params.fetch(:operation_id)
        raise ActiveRecord::RecordNotFound unless Operation::Thick::ID.match?(id)

        @surface = requested_surface
        @surface ||= EditorExport::SURFACES[request.request_parameters["editor"]] if action_name == "apply"
        @operation = OperationCatalog.find(@site, id, surface: @surface, **@catalog_options)
        @operation ||= OperationCatalog.find(@site, id, surface: :both, **@catalog_options) if @surface
        raise ActiveRecord::RecordNotFound unless @operation&.source == :thick

        @requirements = serializer.applicable_context(@operation)
      rescue ArgumentError => error
        invalid_run(error)
      end

      def invalid_run(error, kind: :invalid_binding, **details)
        @errors = [{step_index: nil, step_operation_id: @operation&.id, kind: kind, detail: error.message}]
        if request.format.json? || action_name == "apply"
          render json: serializer.errors(@errors).merge(details), status: 422
        else
          render turbo_stream: turbo_stream.replace("validation_panel", partial: "studio/macro_maker/run_validation"), status: 422
        end
      end

      def serializer
        @serializer ||= Serializer.new(command_schema_directory: @catalog_options.fetch(:command_schema_directory))
      end

      def bindings(body, name)
        value = body.fetch(name, {})
        value = JSON.parse(value) if value.is_a?(String)
        raise ArgumentError, "#{name.capitalize} must be an object" unless value.is_a?(Hash)

        value
      end

      def owned_results = RenderResult.where(site: @site, user: @user)

      def recent_runs
        owned_results.where(operation_id: @operation.id, surface: @operation.surface.to_s)
          .with_attached_output.with_attached_source_project.order(created_at: :desc, id: :desc).limit(10)
      end

      def result_payload(result)
        payload = {id: result.id, status: result.status}
        payload[:download_url] = studio_macro_maker_download_run_path(result) if result.downloadable_output
        payload[:project_download_url] = studio_macro_maker_download_run_path(result, file: "project") if result.downloadable_project
        unless result.terminal?
          payload[:status_url] = studio_macro_maker_run_status_path(result)
          payload[:progress] = Rails.cache.read(result.progress_cache_key) if result.status == "running"
        end
        payload[:error] = result.error_message if result.failed?
        payload
      end

      def result_status = @result.failed? ? 422 : (@result.terminal? ? 200 : 202)

      def render_result
        status = result_status
        if request.format.json?
          render json: result_payload(@result), status: status
        else
          @recent_runs = recent_runs
          streams = [
            turbo_stream.replace("validation_panel", partial: "studio/macro_maker/run_validation"),
            turbo_stream.replace("macro_recent_runs", partial: "studio/macro_maker/recent_runs")
          ]
          unless @result.terminal?
            streams << turbo_stream.replace("macro_run_button", partial: "studio/macro_maker/run_button",
              locals: {pending_run: @result})
          end
          render turbo_stream: streams, status: status
        end
      end
    end
  end
end
