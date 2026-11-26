require_relative "recipe"

module Studio
  module HandleType
    TYPES = (Recipe::TYPES + %w[mask image composition keyframe any]).freeze
    CONCRETE = (TYPES - ["any"]).freeze

    def self.returns(mapping, produced)
      raise ArgumentError, "Returns must be a map" unless mapping.is_a?(Hash)

      mapping.to_h do |name, type|
        unless name.is_a?(String) && Recipe::NAME.match?(name) && produced.include?(name)
          raise ArgumentError, "Unknown returned handle: #{name}"
        end
        raise ArgumentError, "Invalid returned handle type #{type.inspect} for #{name}" unless CONCRETE.include?(type)

        [name, type]
      end.freeze
    end

    def self.accepts(mapping, parameters, verify_names: true)
      raise ArgumentError, "Accepts must be a map" unless mapping.is_a?(Hash)

      mapping.to_h do |name, type_or_types|
        unless name.is_a?(String) && !name.empty? && (!verify_names || parameters.include?(name))
          raise ArgumentError, "Unknown accepting parameter: #{name}"
        end
        types = type_or_types.is_a?(Array) ? type_or_types : [type_or_types]
        unless types.length.between?(1, TYPES.length) && types.uniq == types && (types - TYPES).empty?
          raise ArgumentError, "Invalid accepted handle types for #{name}"
        end

        [name, types.freeze]
      end.freeze
    end

    def self.from_schema(schema)
      return unless schema.is_a?(Hash)

      type = schema["studio_type"]
      return type if CONCRETE.include?(type)

      type = schema["type"]
      type = "number" if type == "integer"
      return type if CONCRETE.include?(type) || type == "boolean"

      values = schema["enum"]
      if values.is_a?(Array) && !values.empty?
        return "string" if values.all? { |value| value.is_a?(String) }
        return "number" if values.all? { |value| value.is_a?(Numeric) }
      end
      nil
    end

    def self.at_path(type, path)
      path.reduce(type) do |current, index|
        next unless index.is_a?(Integer) && index >= 0

        case current
        when "polygon" then "point"
        when "point" then "number" if index < 2
        end
      end
    end
  end
end
