# frozen_string_literal: true
require 'json'
module NevaehIntelligences
  module Factory
    module Runtime
      module_function
      def call(definition:, inputs:)
        Contract.inputs!(definition.fetch('input_schema'), inputs)
        value = JSON.parse(JSON.generate(inputs))
        definition.fetch('steps').each do |step|
          case step.fetch('op')
          when 'select' then value = value.slice(*step.fetch('fields'))
          when 'require'
            missing = step.fetch('fields').reject { |field| value.key?(field) && !value[field].nil? && value[field] != '' }
            raise ArgumentError, "Missing output fields: #{missing.join(', ')}" if missing.any?
          when 'rename'
            renamed = value.dup
            step.fetch('mapping').each do |from, to|
              next unless value.key?(from)
              raise ArgumentError, "Rename collides with #{to}" if from != to && value.key?(to) && !step['mapping'].key?(to)
              renamed.delete(from)
            end
            step.fetch('mapping').each { |from, to| renamed[to] = value[from] if value.key?(from) }
            value = renamed
          when 'normalize'
            field = step.fetch('field')
            raise ArgumentError, "#{field} must be text for normalization" unless value[field].is_a?(String)
            value[field] = case step.fetch('mode')
            when 'strip' then value[field].strip
            when 'downcase' then value[field].downcase
            when 'upcase' then value[field].upcase
            when 'slug' then value[field].downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
            end
          when 'defaults' then value = step.fetch('values').merge(value)
          when 'template'
            value[step.fetch('field')] = step.fetch('text').gsub(/\{([^{}]+)\}/) do
              item = value.fetch(Regexp.last_match(1)) { raise ArgumentError, 'Template references a missing field' }
              raise ArgumentError, 'Template values must be scalar' if item.is_a?(Hash) || item.is_a?(Array)
              item.to_s
            end
          end
          raise ArgumentError, 'Construction output exceeds 64 KB' if JSON.generate(value).bytesize > 64000
        end
        value
      end
    end
  end
end
