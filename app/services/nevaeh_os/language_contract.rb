# frozen_string_literal: true
module NevaehOs
  module LanguageContract
    TYPES = %w[string integer number boolean].freeze
    COMMANDS = {
      'project'=>%w[kind name], 'ticket'=>%w[kind text], 'run'=>%w[kind id],
      'worker_status'=>%w[kind id status], 'resource'=>%w[kind operation resource id attributes],
      'capability'=>%w[kind intent payload], 'write'=>%w[kind format context]
    }.freeze
    module_function
    def validate!(patterns:, slots:, command:, sources:)
      raise ArgumentError, 'Provide 1–20 phrase patterns under 400 characters' unless patterns.is_a?(Array) && patterns.length.between?(1, 20) && patterns.all? { |p| p.is_a?(String) && p.strip.length.between?(3, 400) }
      raise ArgumentError, 'Declare up to twelve typed slots' unless slots.is_a?(Hash) && slots.length <= 12 && slots.all? { |key, type| key.match?(/\A[a-z][a-z0-9_]{0,40}\z/) && TYPES.include?(type) }
      patterns.each do |pattern|
        fields = pattern.scan(/\{([a-z][a-z0-9_]*)\}/).flatten
        raise ArgumentError, 'Each pattern must contain every declared slot once' unless fields.sort == slots.keys.sort && fields.uniq == fields
        raise ArgumentError, 'Use literal words between slots' if pattern.match?(/\}\s*\{/)
        raise ArgumentError, 'Invalid pattern braces' if pattern.gsub(/\{[a-z][a-z0-9_]*\}/, '').match?(/[{}]/)
      end
      raise ArgumentError, 'Use a supported typed operating command' unless command.is_a?(Hash) && COMMANDS.key?(command['kind']) && (command.keys - COMMANDS.fetch(command['kind'])).empty? && command.to_json.bytesize <= 8000
      required = case command['kind']
        when 'project' then %w[name]
        when 'ticket' then %w[text]
        when 'run' then %w[id]
        when 'worker_status' then %w[id status]
        when 'resource' then %w[operation resource attributes]
        when 'capability' then %w[intent payload]
        when 'write' then %w[format context]
        end
      raise ArgumentError, 'Command template is missing required fields' unless required.all? { |key| command.key?(key) }
      %w[payload attributes context].each { |key| raise ArgumentError, "#{key} must be an object" if command.key?(key) && !command[key].is_a?(Hash) }
      %w[id name text].each do |key|
        next unless command.key?(key)
        value = command[key]; expected = key == 'id' ? 'integer' : 'string'
        placeholder = value.is_a?(String) && value.match(/\A\{([a-z][a-z0-9_]*)\}\z/)
        valid = placeholder ? slots[placeholder[1]] == expected : expected == 'integer' ? value.is_a?(Integer) && value.positive? : value.is_a?(String) && value.strip.length.between?(1, 1000)
        raise ArgumentError, "#{key} needs a #{expected} value or matching typed slot" unless valid
      end
      found = []
      walk = lambda do |value|
        case value
        when Hash then value.each_value { |entry| walk.call(entry) }
        when Array then value.each { |entry| walk.call(entry) }
        when String
          if (match = value.match(/\A\{([a-z][a-z0-9_]*)\}\z/))
            found << match[1]
          elsif value.include?('{') || value.include?('}')
            raise ArgumentError, 'A command placeholder must fill a whole value'
          end
        when Integer, TrueClass, FalseClass, NilClass
          nil
        when Float
          raise ArgumentError, 'Numbers must be finite' unless value.finite?
        else raise ArgumentError, 'Unsupported template value'
        end
      end
      walk.call(command)
      raise ArgumentError, 'Command placeholders must match the declared slots' unless found.uniq.sort == slots.keys.sort
      raise ArgumentError, 'At least one versioned manual reference is required' unless sources.is_a?(Array) && sources.length.between?(1, 10) && sources.all? { |s| s.is_a?(Hash) && s['path'].is_a?(String) && s['path'].length <= 500 && s['sha256'].to_s.match?(/\A[0-9a-f]{64}\z/) }
      true
    end
    def match(binding, text)
      binding.patterns.filter_map do |pattern|
        fields = []
        parts = pattern.split(/(\{[a-z][a-z0-9_]*\})/).map do |part|
          if part.match?(/\A\{[a-z][a-z0-9_]*\}\z/)
            fields << part[1...-1]
            '(.+?)'
          else
            part.split(/(\s+)/).map { |piece| piece.match?(/\A\s+\z/) ? '\s+' : Regexp.escape(piece) }.join
          end
        end
        match = Regexp.new("\\A#{parts.join}\\z", Regexp::IGNORECASE, timeout: 0.02).match(text.strip)
        next unless match
        values = fields.each_with_index.to_h { |field, index| [field, coerce(match[index + 1], binding.slots.fetch(field))] }
        render(binding.command_template, values)
      end.uniq
    rescue Regexp::TimeoutError
      raise ArgumentError, 'Phrase matching exceeded its budget; simplify this pattern'
    end
    def coerce(value, type)
      text = value.strip
      case type
      when 'integer'
        raise ArgumentError, 'Use a whole-number input' unless text.match?(/\A-?[0-9]{1,10}\z/)
        Integer(text, 10)
      when 'number'
        raise ArgumentError, 'Use a finite numeric input' unless text.match?(/\A-?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?\z/i)
        number = Float(text)
        raise ArgumentError, 'Use a finite numeric input' unless number.finite?
        number
      when 'boolean'
        return true if %w[true yes].include?(text.downcase)
        return false if %w[false no].include?(text.downcase)
        raise ArgumentError, 'Use yes/no or true/false'
      else
        text = text[1...-1] if text.length >= 2 && [['"','"'], ['“','”']].include?([text[0], text[-1]])
        raise ArgumentError, 'Text inputs need 1–1000 characters' unless text.length.between?(1, 1000)
        text
      end
    end
    def render(value, slots)
      case value
      when Hash then value.transform_values { |entry| render(entry, slots) }
      when Array then value.map { |entry| render(entry, slots) }
      when String
        match = value.match(/\A\{([a-z][a-z0-9_]*)\}\z/)
        match ? slots.fetch(match[1]) : value
      else value
      end
    end
    def verify_command!(binding, command)
      captured = {}
      verify = lambda do |template, actual|
        case template
        when Hash
          actual.is_a?(Hash) && actual.keys.sort == template.keys.sort && template.all? { |key, value| verify.call(value, actual[key]) }
        when Array
          actual.is_a?(Array) && actual.length == template.length && template.each_with_index.all? { |value, index| verify.call(value, actual[index]) }
        when String
          if (placeholder = template.match(/\A\{([a-z][a-z0-9_]*)\}\z/))
            key = placeholder[1]; type = binding.slots.fetch(key)
            valid = case type
              when 'integer' then actual.is_a?(Integer)
              when 'number' then actual.is_a?(Numeric) && actual.finite?
              when 'boolean' then actual == true || actual == false
              else actual.is_a?(String) && actual.length.between?(1, 1000)
              end
            consistent = !captured.key?(key) || captured[key] == actual
            captured[key] = actual
            valid && consistent
          else
            template == actual
          end
        else template == actual
        end
      end
      # These fields come from operating/agent context. The executor checks them.
      actual = command.except('language_binding', 'agent_id', 'persona_id', 'site_id', 'origin')
      raise ArgumentError, 'The saved task does not match its reviewed conversational action' unless verify.call(binding.command_template, actual)
    end
  end
end
