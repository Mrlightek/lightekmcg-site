module Studio
  class CompositionCompiler
    class BindingError < ArgumentError
      attr_reader :index, :operation_id

      def initialize(step, message)
        @index = step.index
        @operation_id = step.operation.id
        super(message)
      end
    end

    def initialize(steps, reserved_handles)
      @steps = steps
      @used = reserved_handles.to_h { |name| [name, true] }
    end

    def commands
      @steps.flat_map do |step|
        step.operation.source == :thin ? [thin_command(step)] : thick_commands(step)
      rescue ArgumentError, KeyError, IndexError => failure
        raise BindingError.new(step, failure.message)
      end
    end

    private

    def thin_command(step)
      returns = step.returns.transform_values { |name| step.operation.result_path(name) }
      {"command" => step.operation.command_id, "params" => step.params, "returns" => returns}
    end

    def thick_commands(step)
      operation = step.operation
      aliases = step.returns.invert
      names = operation.recipe.return_names.to_h { |name| [name, aliases[name] || reserve(step.index, name)] }
      bindings = operation.composition_bindings(step.params, step.inputs)
      JSON.parse(operation.recipe.to_json).fetch("steps").map do |command|
        command.merge("params" => expand(command.fetch("params"), bindings, names),
          "returns" => command.fetch("returns", {}).transform_keys { |name| names.fetch(name) })
      end
    end

    def expand(node, bindings, names)
      case node
      when Array
        node.map { |value| expand(value, bindings, names) }
      when Hash
        token = (node.keys & Recipe::TOKENS).first
        return node.transform_values { |value| expand(value, bindings, names) } unless token

        binding, *path = Array(node.fetch(token))
        if token == "$ref"
          reference(token, names.fetch(binding), path)
        else
          project(bindings.fetch(token).fetch(binding), path)
        end
      else
        node
      end
    end

    def project(value, path)
      if value.is_a?(Hash) && (token = (value.keys & Recipe::TOKENS).first)
        binding, *prefix = Array(value.fetch(token))
        return reference(token, binding, prefix + path)
      end

      path.reduce(value) { |node, index| node.fetch(index) }
    rescue NoMethodError, TypeError
      raise ArgumentError, "Invalid projected binding for path #{path.inspect}"
    end

    def reference(token, binding, path)
      {token => path.empty? ? binding : [binding, *path]}
    end

    def reserve(index, name)
      candidate = "composition_step_#{index}_#{name}"
      candidate += "_" while @used[candidate]
      @used[candidate] = true
      candidate
    end
  end
end
