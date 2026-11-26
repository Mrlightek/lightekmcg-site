module Studio
  module MacroMaker
    class EditorController < WorkspaceController
      def index
        @surface = requested_surface || "image"
        @records = @store.list(@surface).select do |record|
          editable?(record.body.fetch("composition").fetch("definition"))
        end
        @run_operations = OperationCatalog.for_site(@site, **@catalog_options, include_thin: false, match_display_names: false)
          .select { |operation| operation.origin == :builtin && [@surface.to_sym, :both].include?(operation.surface) }
        render "studio/macro_maker/index"
      end

      def new
        @definition = {"id" => "", "name" => "", "description" => "", "surface" => requested_surface || "image",
          "parameters" => {}, "inputs" => {}, "steps" => []}
        render_editor
      end

      def edit
        version = request.query_parameters["version"]
        raise ActiveRecord::RecordNotFound if version && !(version.is_a?(String) && version.match?(/\A[1-9]\d*\z/))

        @record = @store.find!(params.fetch(:operation_id), requested_surface, version: version)
        @definition = @record.body.fetch("composition").fetch("definition")
        raise ActiveRecord::RecordNotFound unless editable?(@definition)

        render_editor
      end

      def create
        published = params.fetch(:publish)
        raise ArgumentError, "Choose Save Draft or Publish" unless %w[draft publish].include?(published)

        definition = JSON.parse(params.fetch(:definition))
        raise ArgumentError, "Definition must be an object" unless definition.is_a?(Hash)

        @record = @store.create!(definition, published: published == "publish")
        @definition = @record.body.fetch("composition").fetch("definition")
        load_operations
        render turbo_stream: [
          turbo_stream.replace("composition_header", partial: "studio/macro_maker/header"),
          turbo_stream.replace("composition_steps", partial: "studio/macro_maker/steps"),
          turbo_stream.replace("validation_panel", partial: "studio/macro_maker/validation",
            locals: {message: @record.published? ? "Published version #{@record.version}" : "Saved draft version #{@record.version}"})
        ]
      rescue Composition::Invalid => error
        render_invalid(error.errors)
      rescue JSON::ParserError, ArgumentError, KeyError => error
        render_invalid([{step_index: nil, step_operation_id: nil, kind: :invalid_binding, detail: error.message}])
      rescue ActiveRecord::RecordInvalid => error
        render_invalid(error.record.errors.full_messages.map do |message|
          {step_index: nil, step_operation_id: nil, kind: :invalid_binding, detail: message}
        end)
      end

      private

      def editable?(definition)
        definition.fetch("steps").all? { |step| Operation::Thick::ID.match?(step.fetch("operation")) }
      end

      def render_editor
        load_operations
        render "studio/macro_maker/editor"
      end

      def load_operations
        serializer = Serializer.new(command_schema_directory: @catalog_options.fetch(:command_schema_directory))
        @operations = OperationCatalog.for_site(@site, **@catalog_options, include_thin: false, match_display_names: false)
          .map { |operation| serializer.operation_detail(operation).with_indifferent_access }
      end

      def render_invalid(errors)
        render turbo_stream: turbo_stream.replace("validation_panel", partial: "studio/macro_maker/validation",
          locals: {errors: errors}), status: :unprocessable_entity
      end
    end
  end
end
