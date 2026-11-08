# frozen_string_literal: true
require 'json'
module NevaehIntelligences
  module Factory
    module Contract
      OPERATIONS = %w[select rename normalize defaults template require].freeze
      FIELD = /\A[a-z][a-z0-9_]{0,60}\z/
      TYPES = %w[string number boolean object array].freeze
      module_function
      def validate!(definition, tests)
        raise ArgumentError, 'Definition needs input_schema and steps' unless definition.is_a?(Hash) && definition.keys.sort == %w[input_schema steps]
        schema = definition['input_schema']
        raise ArgumentError, 'Use 1–30 typed input fields' unless schema.is_a?(Hash) && schema.length.between?(1, 30)
        schema.each do |field, type|
          raise ArgumentError, 'Invalid input field or type' unless field.is_a?(String) && FIELD.match?(field) && TYPES.include?(type)
        end
        steps = definition['steps']
        raise ArgumentError, 'Use 1–30 construction steps' unless steps.is_a?(Array) && steps.length.between?(1, 30)
        steps.each do |step|
          raise ArgumentError, 'Unknown construction operation' unless step.is_a?(Hash) && OPERATIONS.include?(step['op']) && (step.keys - %w[op fields mapping mode field text values]).empty?
          case step['op']
          when 'select', 'require'
            raise ArgumentError, 'Choose 1–30 field names' unless step['fields'].is_a?(Array) && step['fields'].length.between?(1, 30) && step['fields'].all? { |v| v.is_a?(String) && FIELD.match?(v) }
          when 'rename'
            raise ArgumentError, 'Renames require field-name mappings' unless step['mapping'].is_a?(Hash) && step['mapping'].length.between?(1, 30) && step['mapping'].values.uniq.length == step['mapping'].length && step['mapping'].all? { |k, v| k.is_a?(String) && v.is_a?(String) && FIELD.match?(k) && FIELD.match?(v) }
          when 'normalize'
            raise ArgumentError, 'Choose a field and strip, downcase, upcase or slug' unless step['field'].is_a?(String) && FIELD.match?(step['field']) && %w[strip downcase upcase slug].include?(step['mode'])
          when 'defaults'
            raise ArgumentError, 'Defaults must be a bounded object' unless step['values'].is_a?(Hash) && step['values'].size <= 30 && step['values'].keys.all? { |k| FIELD.match?(k) }
          when 'template'
            raise ArgumentError, 'Template needs an output field and text' unless step['field'].is_a?(String) && FIELD.match?(step['field']) && step['text'].is_a?(String) && step['text'].length.between?(1, 4000)
            raise ArgumentError, 'Use simple {field} placeholders' unless step['text'].scan(/\{([^{}]+)\}/).flatten.all? { |v| FIELD.match?(v) }
          end
        end
        raise ArgumentError, 'Add 1–20 sample tests with inputs and exact expected output' unless tests.is_a?(Array) && tests.length.between?(1, 20) && tests.all? { |test| test.is_a?(Hash) && test.keys.sort == %w[expected inputs] && test['inputs'].is_a?(Hash) && test['expected'].is_a?(Hash) }
        raise ArgumentError, 'Construction exceeds 100 KB' if JSON.generate([definition, tests]).bytesize > 100000
        true
      end
      def inputs!(schema, values)
        raise ArgumentError, 'Inputs must be a bounded object' unless values.is_a?(Hash) && JSON.generate(values).bytesize <= 16000
        raise ArgumentError, "Missing inputs: #{(schema.keys - values.keys).join(', ')}" if (schema.keys - values.keys).any?
        raise ArgumentError, 'Unknown inputs' if (values.keys - schema.keys).any?
        schema.each do |field, type|
          value = values[field]
          valid = case type
          when 'string' then value.is_a?(String)
          when 'number' then value.is_a?(Numeric) && value.finite?
          when 'boolean' then value == true || value == false
          when 'object' then value.is_a?(Hash)
          when 'array' then value.is_a?(Array)
          end
          raise ArgumentError, "#{field} must be #{type}" unless valid
        end
        values
      end
    end
  end
end
