module Studio
  module MacroMaker
    class Serializer
      SCHEMA_PATH = "config/studio/schemas/macro_maker_v1.schema.json".freeze

      def initialize(command_schema_directory:)
        @command_schema_directory = command_schema_directory
        @metadata_by_engine = {}
      end

      def catalog(operations, engines:)
        {thick_operations: operations.map { |operation| operation_detail(operation).merge(
          applicable_context: applicable_context(operation)) },
          surfaces: %w[image motion], engines: engines}
      end

      def operation_detail(operation)
        {id: operation.id, display_name: operation.display_name, description: operation.description,
          surface: operation.surface, origin: operation.origin, version: operation.recipe.version,
          runnable: operation.runnable?}.merge(interfaces(operation))
      end

      def validation(recipe, warnings:)
        {valid: true, compiled_recipe: JSON.parse(recipe.to_json), warnings: issues(warnings)}
      end

      def created(record)
        {id: record.id, version: record.version, surface: record.surface, operation_id: record.operation_id,
          published: record.published?, created_at: record.created_at.iso8601(6)}
      end

      def composition_list(records)
        {compositions: records.map { |record| created(record).merge(definition: source_definition(record)) }}
      end

      def composition_detail(record, operation)
        body = record.body
        created(record).merge(
          definition: source_definition(record), compiled_recipe: body.fetch("recipe"),
          references: body.fetch("composition").fetch("references")
        ).merge(interfaces(operation))
      end

      def errors(errors)
        {valid: false, errors: issues(errors)}
      end

      def applicable_context(operation)
        metadata = @metadata_by_engine[operation.engine] ||= Operation::CommandMetadata.load(@command_schema_directory, operation.engine)
        operation.recipe.command_ids.flat_map { |command| metadata[command]&.requires || [] }.uniq.sort
      end

      private

      def source_definition(record) = record.body.fetch("composition").fetch("definition")

      def interfaces(operation)
        {params_schema: form_schema(operation.params_schema), inputs_schema: form_schema(operation.inputs_schema),
          returns: operation.returns, accepts: operation.accepts}
      end

      def issues(entries)
        entries.map do |entry|
          {step_index: entry.fetch(:step_index), step_operation_id: entry.fetch(:step_operation_id),
            kind: entry.fetch(:kind), detail: entry.fetch(:detail)}
        end
      end

      def form_schema(controls)
        properties = controls.transform_values do |spec|
          type = spec.fetch("type")
          number = {type: "number"}
          number[:minimum] = spec.fetch("min") if spec.key?("min")
          number[:maximum] = spec.fetch("max") if spec.key?("max")
          point = {type: "array", items: number, minItems: 2, maxItems: 2}
          property = case type
          when "number" then number
          when "point" then point.merge(studio_type: "point")
          when "polygon" then {type: "array", items: point, minItems: 3, maxItems: 1024, studio_type: "polygon"}
          when "color" then {type: "string", pattern: "^#[0-9a-fA-F]{6}$", studio_type: "color"}
          when "layer_id" then {type: "integer", minimum: 1, studio_type: "layer_id"}
          when "string" then {type: "string", minLength: 1, maxLength: 120}
          end
          spec.key?("default") ? property.merge(default: spec.fetch("default")) : property
        end
        {type: "object", properties: properties, required: controls.reject { |_, spec| spec.key?("default") }.keys,
          additionalProperties: false}
      end
    end
  end
end
