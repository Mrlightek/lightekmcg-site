module Studio
  class CompositionValidator
    Step = Data.define(:index, :operation, :params, :inputs, :returns)

    def initialize(definition, catalog, ancestry:)
      @definition = definition
      surface = definition.fetch("surface").to_sym
      entries = catalog.select { |entry| entry.surface == surface || entry.surface == :both }
      @operations = entries.sort_by { |entry| entry.surface == surface ? 0 : 1 }.uniq(&:id).to_h { |entry| [entry.id, entry] }
      @ancestry = ancestry
      @steps = []
      @errors = []
      @handles = {}
      @seen_handles = {}
    end

    def validate!
      steps = @definition["steps"]
      unless steps.is_a?(Array) && !steps.empty?
        raise Composition::Invalid.new([{step_index: nil, step_operation_id: nil,
          kind: :invalid_binding, detail: "Composition needs at least one step"}])
      end
      steps.each_with_index { |step, index| validate_step(step, index) }
      raise Composition::Invalid.new(@errors) unless @errors.empty?

      [@steps, @handles]
    end

    private

    def validate_step(data, index)
      @index = index
      @id = data["operation"] if data.is_a?(Hash)
      @id = nil unless data.is_a?(Hash) && @id.is_a?(String)
      unless data.is_a?(Hash) && @id.is_a?(String) && (data.keys - %w[operation params inputs returns]).empty?
        return error(:invalid_binding, "Step needs an operation ID and optional params, inputs and returns maps")
      end

      operation = @operations[@id]
      return error(:unknown_operation, "Operation #{@id} is not in this site's #{@definition.fetch('surface')} catalog") unless operation

      @engine ||= operation.engine
      error(:invalid_binding, "A composition cannot mix #{@engine} and #{operation.engine} commands") if @engine != operation.engine
      params = object(data, "params")
      inputs = object(data, "inputs")
      returns = object(data, "returns")
      validate_bindings(operation, params, "parameter")
      validate_bindings(operation, inputs, "input")
      validate_captures(operation, returns)
      validate_nested(operation)
      @steps << Step.new(index: index, operation: operation, params: params, inputs: inputs, returns: returns)
    end

    def validate_bindings(operation, bindings, kind)
      if operation.source == :thick
        schema = kind == "input" ? operation.inputs_schema : operation.params_schema
        (bindings.keys - schema.keys).each { |name| error(:invalid_binding, "Unknown #{kind} #{name}") }
        if kind == "input"
          schema.each do |name, spec|
            error(:invalid_binding, "Missing required operation input #{name}") unless bindings.key?(name) || spec.key?("default")
          end
        end
      elsif kind == "input" && !bindings.empty?
        error(:invalid_binding, "Thin commands accept their arguments in params")
      end

      bindings.each do |name, value|
        found_binding = visit(operation, kind, name, value, [])
        next if found_binding || !schema&.key?(name)

        begin
          operation.validate_literal!(kind, name, value)
        rescue ArgumentError => failure
          error(:invalid_binding, failure.message)
        end
      end
    end

    def visit(operation, kind, name, node, argument_path)
      case node
      when Array
        node.each_with_index.map { |value, index| visit(operation, kind, name, value, argument_path + [index]) }.any?
      when Hash
        tokens = node.keys & Recipe::TOKENS
        if tokens.empty?
          return node.map { |key, value| visit(operation, kind, name, value, argument_path + [key]) }.any?
        end

        if node.size == 1
          check_token(operation, kind, name, tokens.first, node.fetch(tokens.first), argument_path)
        else
          error(:invalid_binding, "A binding token must be the only key for #{name}")
        end
        true
      else
        false
      end
    end

    def check_token(operation, kind, name, token, value, argument_path)
      binding, *path = value.is_a?(Array) ? value : [value]
      unless binding.is_a?(String) && path.all? { |part| (part.is_a?(Integer) && part >= 0) || (part.is_a?(String) && !part.empty?) }
        return error(:invalid_binding, "Malformed #{token} for #{name}")
      end

      if token == "$ref"
        type = @handles[binding]
        return error(:unresolved_ref, "Handle #{binding} is not produced by a prior step") unless type
      else
        schema = token == "$param" ? "parameters" : "inputs"
        declaration = @definition.fetch(schema, {})[binding]
        return error(:invalid_binding, "Undeclared #{token} #{binding}") unless declaration
        type = HandleType.from_schema(declaration)
      end

      actual = HandleType.at_path(type, path)
      return error(:invalid_binding, "Cannot project #{type} via #{path.inspect} for #{name}") unless actual

      native = HandleType.at_path(operation.native_type(name, kind), argument_path)
      explicit = operation.accepts[name] if argument_path.empty?
      accepted = if token == "$ref"
        explicit || [native].compact
      else
        native ? [native] : explicit
      end
      return if accepted.nil? || accepted.include?("any") || accepted.include?(actual)

      expected = accepted.empty? ? "no declared handle type" : accepted.join(" or ")
      error(:type_mismatch, "#{name} accepts #{expected}, received #{actual} from #{binding}")
    end

    def validate_captures(operation, captures)
      seen_outputs = {}
      captures.each do |handle, output|
        unless Recipe::NAME.match?(handle) && output.is_a?(String) && operation.returns.key?(output)
          error(:invalid_binding, "Unknown or invalid return #{output.inspect} for handle #{handle}")
          next
        end
        if @seen_handles[handle] || seen_outputs[output]
          error(:invalid_binding, "Duplicate returned handle #{handle} or output #{output}")
          next
        end

        @seen_handles[handle] = true
        seen_outputs[output] = true
        @handles[handle] = operation.returns.fetch(output)
      end
    end

    def validate_nested(operation)
      operation.recipe.validate_current!(ancestry: @ancestry) if operation.source == :thick
    rescue Composition::Invalid => failure
      error(:invalid_binding, "Referenced composition #{operation.id} is stale: #{failure.message}")
    end

    def object(data, key)
      value = data.fetch(key, {})
      return value if value.is_a?(Hash)

      error(:invalid_binding, "#{key} must be a map")
      {}
    end

    def error(kind, detail)
      @errors << {step_index: @index, step_operation_id: @id, kind: kind, detail: detail}
    end
  end
end
