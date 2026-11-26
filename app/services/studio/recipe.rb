require "json"
require "tempfile"
require_relative "recipe_session"

module Studio
  class Recipe
    ENGINES = RecipeSession::ADAPTERS.keys.freeze
    TYPES = %w[number point color string layer_id polygon].freeze
    TOKENS = %w[$param $input $ref].freeze
    NAME = /\A[a-z][a-z0-9_]*\z/
    PARAMETER_NAME = /\A[a-z][a-zA-Z0-9_]*\z/
    COMMAND = /\A[a-z][a-z0-9]*(?:\.[a-z0-9_]+)+\z/i

    def self.load(path)
      new(JSON.parse(File.read(path)))
    end

    def initialize(definition, before_run: nil)
      @definition = JSON.parse(JSON.generate(definition))
      validate_definition!
      @before_run = before_run
    end

    def name = @definition.fetch("name")
    def version = @definition.fetch("version")
    def engine = @definition.fetch("engine")
    def command_ids = @definition.fetch("steps").map { |step| step.fetch("command") }.uniq
    def return_names = @definition.fetch("steps").flat_map { |step| step.fetch("returns", {}).keys }

    def validate_current!(ancestry: [])
      @before_run&.call(ancestry)
    end

    def validate_binding!(kind, name, value)
      schema = @definition.fetch({"parameter" => "parameters", "input" => "inputs"}.fetch(kind), {})
      validate_value!(name, value, schema.fetch(name), kind)
    end

    def to_json(*options)
      @definition.to_json(*options)
    end

    # Expand caller values. Result handles are resolved in the live engine session.
    def commands(overrides = {}, inputs: {}, **inline_overrides)
      parameters = bind(@definition.fetch("parameters"), overrides.merge(inline_overrides), "parameter")
      runtime = bind(@definition.fetch("inputs", {}), inputs, "input")
      @definition.fetch("steps").map do |step|
        step.merge("params" => resolve(step.fetch("params"), {"$param" => parameters, "$input" => runtime}))
      end
    end

    def run!(executable:, input: nil, output:, parameters: {}, inputs: {}, total_timeout: RecipeSession::DEFAULT_TOTAL_TIMEOUT)
      validate_current!
      steps = commands(parameters, inputs: inputs)
      destination = File.expand_path(output)
      source = File.expand_path(input) if input
      raise ArgumentError, "Choose a new output path" if File.exist?(destination) || source == destination

      handles = {}
      Tempfile.create([".studio-recipe-", File.extname(destination)], File.dirname(destination)) do |file|
        staged = file.path
        file.close
        RecipeSession.open(engine, executable, source, staged, total_timeout: total_timeout) do |adapter, session|
          steps.each_with_index do |step, index|
            command = step.fetch("command")
            timeout = step.fetch("timeout", RecipeSession::DEFAULT_STEP_TIMEOUT)
            session.step(step_index: index, command: command, timeout: timeout) do
              arguments = resolve(step.fetch("params"), {"$ref" => handles})
              result = adapter.execute(command, arguments)
              step.fetch("returns", {}).each do |handle, path|
                handles[handle] = extract(result, path, "return handle #{handle} from #{command}")
              end
            end
          end

          session.step(step_index: nil, command: "save") do
            adapter.save(staged)
            unless File.file?(staged) && File.size?(staged)
              raise RecipeSession::ProtocolError, "Recipe engine did not create its output"
            end
          end
        end
        File.link(staged, destination)
      end
      destination
    end

    private

    def validate_definition!
      unless @definition.is_a?(Hash) && @definition["name"].is_a?(String) && !@definition["name"].strip.empty? &&
          @definition["version"].is_a?(Integer) && @definition["version"].positive?
        raise ArgumentError, "Recipe needs a name and a positive integer version"
      end
      raise ArgumentError, "Unsupported recipe engine" unless ENGINES.include?(@definition["engine"])

      schemas = {"$param" => @definition["parameters"], "$input" => @definition.fetch("inputs", {})}
      validate_schemas!(schemas)
      steps = @definition["steps"]
      raise ArgumentError, "Recipe needs at least one step" unless steps.is_a?(Array) && !steps.empty?

      declared = {}
      steps.each do |step|
        unless step.is_a?(Hash) && step["command"].is_a?(String) && COMMAND.match?(step["command"]) && step["params"].is_a?(Hash) && (step["params"].keys & TOKENS).empty?
          raise ArgumentError, "Each recipe step needs a command ID and params object"
        end

        if step.key?("timeout") && !RecipeSession.valid_timeout?(step["timeout"])
          raise ArgumentError, "Invalid timeout for #{step.fetch('command')}"
        end

        validate_tokens!(step.fetch("params"), schemas.merge("$ref" => declared))
        returns = step.fetch("returns", {})
        raise ArgumentError, "Step returns must be an object" unless returns.is_a?(Hash)

        returns.each do |handle, path|
          unless NAME.match?(handle) && path.is_a?(Array) && path.all? { |part| path_component?(part) }
            raise ArgumentError, "Invalid return handle: #{handle}"
          end
          raise ArgumentError, "Duplicate return handle: #{handle}" if declared.key?(handle)

          declared[handle] = true
        end
      end
    end

    def validate_schemas!(schemas)
      schemas.each do |token, definitions|
        raise ArgumentError, "Invalid #{token} definitions" unless definitions.is_a?(Hash)

        definitions.each do |name, spec|
          unless binding_name?(token, name) && spec.is_a?(Hash) && TYPES.include?(spec["type"])
            raise ArgumentError, "Invalid #{token} definition: #{name}"
          end
          if %w[number point].include?(spec["type"]) &&
              !(number?(spec["min"]) && number?(spec["max"]) && spec["min"] <= spec["max"])
            raise ArgumentError, "Invalid bounds for #{token} #{name}"
          end
          if (token == "$param" || spec.key?("default")) && !valid?(spec["default"], spec)
            raise ArgumentError, "Invalid default for #{token} #{name}"
          end
        end
      end
    end

    def validate_tokens!(node, declarations)
      case node
      when Array
        node.each { |child| validate_tokens!(child, declarations) }
      when Hash
        token = (node.keys & TOKENS).first
        if token
          value = node.fetch(token)
          parts = value.is_a?(Array) ? value : [value]
          name, *path = parts
          unless node.size == 1 && name.is_a?(String) && binding_name?(token, name) && path.all? { |part| path_component?(part) }
            raise ArgumentError, "Invalid #{token} expression"
          end
          raise ArgumentError, "Unresolved #{token}: #{name}" unless declarations.fetch(token).key?(name)
        else
          node.each_value { |child| validate_tokens!(child, declarations) }
        end
      end
    end

    def bind(schema, overrides, label)
      unknown = overrides.keys - schema.keys
      raise ArgumentError, "Unknown #{label}s: #{unknown.join(', ')}" unless unknown.empty?

      schema.to_h do |name, spec|
        unless overrides.key?(name) || spec.key?("default")
          raise ArgumentError, "Unresolved $input: #{name}"
        end
        value = overrides.fetch(name) { spec.fetch("default") }
        validate_value!(name, value, spec, label)

        [name, value]
      end
    end

    def binding_name?(token, name)
      (token == "$param" ? PARAMETER_NAME : NAME).match?(name)
    end

    def validate_value!(name, value, spec, label)
      raise ArgumentError, "Invalid #{label}: #{name}" unless valid?(value, spec)
    end

    def valid?(value, spec)
      case spec.fetch("type")
      when "number"
        number?(value) && value.between?(spec.fetch("min"), spec.fetch("max"))
      when "point"
        point?(value) && value.all? { |coordinate| coordinate.between?(spec.fetch("min"), spec.fetch("max")) }
      when "color"
        value.is_a?(String) && value.match?(/\A#[0-9a-fA-F]{6}\z/)
      when "string"
        value.is_a?(String) && !value.strip.empty? && value.length <= 120
      when "layer_id"
        value.is_a?(Integer) && value.positive?
      when "polygon"
        value.is_a?(Array) && value.length.between?(3, 1024) && value.all? { |point| point?(point) }
      end
    end

    def number?(value)
      value.is_a?(Numeric) && value.finite?
    end

    def point?(value)
      value.is_a?(Array) && value.size == 2 && value.all? { |coordinate| number?(coordinate) }
    end

    def path_component?(value)
      (value.is_a?(Integer) && value >= 0) || (value.is_a?(String) && !value.empty?)
    end

    def resolve(node, values)
      case node
      when Array
        node.map { |child| resolve(child, values) }
      when Hash
        token = (node.keys & values.keys).first
        return node.transform_values { |child| resolve(child, values) } unless token

        name, *path = Array(node.fetch(token))
        extract(values.fetch(token).fetch(name), path, "#{token} #{name}")
      else
        node
      end
    end

    def extract(result, path, label)
      value = path.reduce(result) do |node, key|
        case node
        when Hash then node[key]
        when Array then node[key] if key.is_a?(Integer)
        end
      end
      raise ArgumentError, "Unresolved #{label}" if value.nil?

      value
    end
  end
end
