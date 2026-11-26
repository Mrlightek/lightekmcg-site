module Studio
  module MacroMaker
    class BaseController < ActionController::API
      CONTEXT_KEY = "lightek.studio.macro_maker".freeze

      before_action :resolve_authorized_context
      before_action :resolve_surface, only: %i[index show]

      rescue_from ArgumentError, ActionController::ParameterMissing, ActionDispatch::Http::Parameters::ParseError do |error|
        render_error(:invalid_binding, error.message, 422)
      end
      rescue_from Composition::Invalid do |error|
        render json: serializer.errors(error.errors), status: 422
      end
      rescue_from ActiveRecord::RecordInvalid do |error|
        render_error(:invalid_binding, error.record.errors.full_messages.join(", "), 422)
      end
      rescue_from ActiveRecord::RecordNotFound do
        render_error(:unknown_operation, "Operation or composition was not found", 404)
      end

      private

      def resolve_authorized_context
        response.headers["Cache-Control"] = "private, no-store"
        context = request.env[CONTEXT_KEY]
        @site = context[:site] if context.is_a?(Hash)
        @user = context[:user] if context.is_a?(Hash)
        unless @site.is_a?(DymondSite::Site) && @site.persisted? && @user.is_a?(User) && @user.persisted?
          return render_error(:missing_context, "An authorized Studio site and user are required", 403)
        end

        @catalog_options = {
          engine_adapters: context.fetch(:engine_adapters) { Operation::EngineAdapter.configured },
          built_in_directory: Rails.root.join("config/studio/operations"),
          command_schema_directory: Rails.root.join("config/studio/command_schemas")
        }
      end

      def resolve_surface
        @surface = request.query_parameters["surface"]
        return unless @surface && !%w[image motion].include?(@surface)

        raise ArgumentError, "Surface must be image or motion"
      end

      def thick_operations
        entries = OperationCatalog.for_site(@site, **@catalog_options, include_thin: false, match_display_names: false)
        return entries unless @surface

        entries.select { |entry| entry.surface == @surface.to_sym || entry.surface == :both }
      end

      def definition
        definition = request.request_parameters["definition"]
        raise ArgumentError, "Definition must be an object" unless definition.is_a?(Hash)

        definition
      end

      def store
        @store ||= CompositionStore.new(site: @site, user: @user, catalog_options: @catalog_options)
      end

      def serializer
        @serializer ||= Serializer.new(command_schema_directory: Rails.root.join("config/studio/command_schemas"))
      end

      def render_error(kind, detail, status)
        error = {step_index: nil, step_operation_id: nil, kind: kind, detail: detail}
        render json: serializer.errors([error]), status: status
      end
    end
  end
end
