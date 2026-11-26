module Studio
  module MacroMaker
    class CompositionsController < BaseController
      def validate
        draft = store.draft(definition)
        render json: serializer.validation(draft.to_recipe, warnings: draft.warnings)
      end

      def create
        published = request.request_parameters.fetch("published", false)
        raise ArgumentError, "Published must be a boolean" unless published == true || published == false

        record = store.create!(definition, published: published)
        render json: serializer.created(record), status: :created
      end

      def index
        render json: serializer.composition_list(store.list(@surface))
      end

      def show
        record = store.find!(request.path_parameters.fetch(:operation_id), @surface)
        operation = record.operation(engine_adapters: @catalog_options.fetch(:engine_adapters), catalog_options: @catalog_options)
        render json: serializer.composition_detail(record, operation)
      end
    end
  end
end
