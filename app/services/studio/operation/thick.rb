require_relative "../handle_type"

module Studio
  module Operation
    class Thick
      ID = /\Astudio\.[a-z][a-z0-9_]*\z/
      SURFACES = %w[image motion both].freeze

      attr_reader :accepts, :returns, :id, :display_name, :surface, :description, :recipe, :origin, :params_schema, :inputs_schema

      def initialize(body, origin: :builtin, engine_adapters: {}, before_run: nil)
        unless body.is_a?(Hash) && body["id"].is_a?(String) && ID.match?(body["id"]) &&
            label?(body["display_name"]) && label?(body["description"]) && SURFACES.include?(body["surface"])
          raise ArgumentError, "Invalid thick operation ID, display name, description or surface"
        end

        @id = body.fetch("id")
        @display_name = body.fetch("display_name").strip
        @surface = body.fetch("surface").to_sym
        @description = body.fetch("description")
        @recipe = Recipe.new(body["recipe"], before_run: before_run)
        @origin = origin
        @adapter = engine_adapters[recipe.engine]
        load_interface!(body["exposes"])
        @returns = HandleType.returns(body.fetch("returns", {}), recipe.return_names)
        @accepts = HandleType.accepts(body.fetch("accepts", {}), params_schema.keys | inputs_schema.keys)
      end

      def engine = recipe.engine
      def native_type(name, kind) = HandleType.from_schema((kind == "input" ? inputs_schema : params_schema)[name])

      def validate_literal!(kind, name, value)
        recipe.validate_binding!(kind, @public_to_internal.fetch(kind).fetch(name), value)
      end

      def composition_bindings(parameters, inputs)
        body = JSON.parse(recipe.to_json)
        {
          "$param" => defaults(body.fetch("parameters")).merge(recipe_bindings(parameters, "parameter")),
          "$input" => defaults(body.fetch("inputs", {})).merge(recipe_bindings(inputs, "input"))
        }
      end

      def source = :thick
      def hidden = false
      def runnable? = !!@adapter&.runnable?

      def validate_run_bindings!(parameters: {}, inputs: {})
        recipe.commands(recipe_bindings(parameters, "parameter"), inputs: recipe_bindings(inputs, "input"))
      end

      def run!(input: nil, output:, parameters: {}, inputs: {}, total_timeout: RecipeSession::DEFAULT_TOTAL_TIMEOUT)
        parameter_bindings = recipe_bindings(parameters, "parameter")
        input_bindings = recipe_bindings(inputs, "input")
        unless runnable?
          raise RecipeSession::StepError.new(step_index: nil, command: "start", engine: engine, reason: :died,
            stderr: "", detail: "#{engine} CLI is unavailable")
        end

        recipe.run!(executable: @adapter.executable, input: input, output: output,
          parameters: parameter_bindings, inputs: input_bindings, total_timeout: total_timeout)
      end

      private

      def defaults(schema)
        schema.select { |_, spec| spec.key?("default") }.transform_values { |spec| spec.fetch("default") }
      end

      def label?(value)
        value.is_a?(String) && !value.strip.empty?
      end

      def load_interface!(exposes)
        raise ArgumentError, "Exposes must be a list" unless exposes.is_a?(Array)

        definition = JSON.parse(recipe.to_json)
        controls = {"parameter" => definition.fetch("parameters"), "input" => definition.fetch("inputs", {})}
        public_schemas = {"parameter" => {}, "input" => {}}
        @public_to_internal = {"parameter" => {}, "input" => {}}
        @fixed = {"parameter" => {}, "input" => {}}
        seen_internal = {}
        seen_public = {}
        exposes.each do |entry|
          kind, name = expose_binding!(entry)
          spec = controls[kind]&.fetch(name, nil)
          raise ArgumentError, "Unknown exposed #{kind}: #{name}" unless spec
          if seen_internal[[kind, name]]
            raise ArgumentError, "Duplicate exposed #{kind}: #{name}"
          end

          seen_internal[[kind, name]] = true
          if entry.key?("value")
            value = entry.fetch("value")
            recipe.validate_binding!(kind, name, value)
            @fixed.fetch(kind)[name] = JSON.parse(JSON.generate(value))
            next
          end

          public_name = entry.fetch("as", name)
          raise ArgumentError, "Invalid public name for #{kind}: #{name}" unless label?(public_name)
          public_name = public_name.strip
          raise ArgumentError, "Duplicate public expose name: #{public_name}" if seen_public[public_name]

          seen_public[public_name] = true
          public_schemas.fetch(kind)[public_name] = spec
          @public_to_internal.fetch(kind)[public_name] = name
        end

        @params_schema = public_schemas.fetch("parameter").freeze
        @inputs_schema = public_schemas.fetch("input").freeze
        hidden_inputs = controls.fetch("input").reject do |name, spec|
          seen_internal[["input", name]] || spec.key?("default")
        end
        unless hidden_inputs.empty?
          raise ArgumentError, "Required inputs must be exposed or fixed: #{hidden_inputs.keys.join(', ')}"
        end
      end

      def expose_binding!(entry)
        unless entry.is_a?(Hash)
          raise ArgumentError, "Each expose must name one parameter or input"
        end

        kinds = entry.keys & %w[parameter input]
        modifiers = entry.keys - kinds
        unless kinds.one? && modifiers.size <= 1 && (modifiers - %w[as value]).empty?
          raise ArgumentError, "Each expose must name one parameter or input with at most one of as or value"
        end

        kind = kinds.first
        [kind, entry.fetch(kind)]
      end

      def recipe_bindings(values, kind)
        mapping = @public_to_internal.fetch(kind)
        hidden = values.keys - mapping.keys
        raise ArgumentError, "Unexposed #{kind}s: #{hidden.join(', ')}" unless hidden.empty?

        @fixed.fetch(kind).merge(values.transform_keys { |name| mapping.fetch(name) })
      end
    end
  end
end
