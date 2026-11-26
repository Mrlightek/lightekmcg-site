require "uri"

module Studio
  module MacroMaker
    class EditorFeaturesController < WorkspaceController
      before_action :authorize_editor_access
      before_action :load_engine

      def show
        @editor_url = ENV["STUDIO_#{@engine.upcase}_EDITOR_URL"]
        url = URI.parse(@editor_url.to_s)
        unless url.is_a?(URI::HTTP) && url.host && !url.userinfo && (url.scheme == "https" || Rails.env.development? || Rails.env.test?)
          return head :service_unavailable
        end

        @editor_origin = "#{url.scheme}://#{url.host}"
        @editor_origin += ":#{url.port}" if url.port != url.default_port
        return head :service_unavailable if @editor_origin == request.base_url

        render "studio/macro_maker/engine_editor"
      rescue URI::InvalidURIError
        head :service_unavailable
      end

      def index
        serializer = Serializer.new(command_schema_directory: @catalog_options.fetch(:command_schema_directory))
        operations = OperationCatalog.for_site(@site, **@catalog_options, include_thin: false, match_display_names: false)
        features = operations.filter_map do |operation|
          next unless operation.engine == @engine && [@surface, "both"].include?(operation.surface.to_s)

          {
            id: operation.id, name: operation.display_name, requires: serializer.applicable_context(operation),
            fields: view_context.render_step_fields(operation, {}, run_form: true)
          }
        end
        render json: {features: features}
      end

      private

      def load_engine
        @engine = params[:editor]
        @surface = EditorExport::SURFACES.fetch(@engine) { raise ActiveRecord::RecordNotFound }
      end
    end
  end
end
