require "yaml"
require_relative "../handle_type"
require_relative "command_results"

module Studio
  module Operation
    class CommandMetadata
      REQUIREMENTS = %w[open_document active_selection selected_layer selection_or_mask open_composition timeline_playhead].freeze
      TYPES = %w[number string boolean color enum point polygon].freeze
      PARAM_FIELDS = %w[type min max default values unit].freeze
      COLOR = /\A#[0-9a-fA-F]{6}\z/

      def self.load(directory, engine)
        file = File.join(directory, "#{engine}.yml")
        return {} unless File.file?(file)

        entries = YAML.safe_load_file(file, aliases: false)
        raise ArgumentError, "Expected a map of command metadata" unless entries.is_a?(Hash)

        entries.to_h do |id, metadata|
          prefix = "#{engine}:"
          unless id.is_a?(String) && id.start_with?(prefix) && id.length > prefix.length
            raise ArgumentError, "Invalid command metadata ID: #{id.inspect}"
          end

          command = id.delete_prefix(prefix)
          [command, new(metadata, result_paths: CommandResults.for(engine, command))]
        rescue ArgumentError => error
          raise ArgumentError, "#{id}: #{error.message}"
        end
      rescue Psych::Exception, ArgumentError => error
        raise ArgumentError, "#{File.basename(file)}: #{error.message}"
      end

      attr_reader :typed_params, :requires, :returns, :accepts

      def initialize(metadata, result_paths: {})
        unless metadata.is_a?(Hash) && (metadata.keys - %w[typed_params requires returns accepts]).empty?
          raise ArgumentError, "Unknown command metadata fields"
        end
        requirements = metadata.fetch("requires", [])
        unless requirements.is_a?(Array) && (requirements - REQUIREMENTS).empty? && requirements == requirements.uniq
          raise ArgumentError, "Unknown or duplicate context requirement: #{requirements.inspect}"
        end
        @requires = requirements.map(&:to_sym).freeze
        @typed_params = metadata.fetch("typed_params", {})
        validate_params!
        @returns = HandleType.returns(metadata.fetch("returns", {}), result_paths.keys)
        @accepts = HandleType.accepts(metadata.fetch("accepts", {}), [], verify_names: false)
      end

      # Preserve the engine schema's required keys, descriptions and untouched properties.
      def merge_schema(native)
        return native if typed_params.empty?

        base = native.is_a?(Hash) ? native : {"type" => "object"}
        properties = base.fetch("properties", {}).dup
        typed_params.each do |name, spec|
          original = properties.fetch(name, {})
          original = {} unless original.is_a?(Hash)
          authored = json_schema(spec)
          native_type = original["type"]
          if native_type && native_type != authored["type"]
            original = original.slice("title", "description", "deprecated")
          else
            original = original.except("$ref", "allOf", "anyOf", "oneOf")
          end
          properties[name] = original.merge(authored).freeze
        end
        base.merge("properties" => properties.freeze).freeze
      end

      def self.typed_schema?(schema)
        return false unless schema.is_a?(Hash)

        properties = schema["properties"]
        return false unless properties.is_a?(Hash)
        return schema["type"] == "object" if properties.empty?

        properties.values.any? do |prop|
          prop.is_a?(Hash) && (prop["type"] || prop["enum"] || prop["oneOf"] || prop["anyOf"])
        end
      end

      private

      def validate_params!
        raise ArgumentError, "typed_params must be a map" unless typed_params.is_a?(Hash)

        typed_params.each do |name, spec|
          unless name.is_a?(String) && !name.strip.empty? && spec.is_a?(Hash) &&
              (spec.keys - PARAM_FIELDS).empty? && TYPES.include?(spec["type"])
            raise ArgumentError, "Malformed typed parameter: #{name.inspect}"
          end

          type = spec.fetch("type")
          bounds = spec.values_at("min", "max")
          if spec.keys.intersect?(%w[min max]) &&
              (!%w[number point].include?(type) || !spec.slice("min", "max").values.all? { |value| number?(value) } ||
                (bounds.all? && bounds[0] > bounds[1]))
            raise ArgumentError, "Invalid bounds for #{name}"
          end
          values = spec["values"]
          if type == "enum"
            unless values.is_a?(Array) && !values.empty? && values == values.uniq &&
                values.all? { |value| value.is_a?(String) || number?(value) || boolean?(value) }
              raise ArgumentError, "Invalid enum values for #{name}"
            end
          elsif spec.key?("values")
            raise ArgumentError, "Enum values require enum type for #{name}"
          end
          if spec.key?("unit") && !(spec["unit"].is_a?(String) && !spec["unit"].strip.empty?)
            raise ArgumentError, "Invalid unit for #{name}"
          end
          if spec.key?("default") && !valid_default?(spec.fetch("default"), spec)
            raise ArgumentError, "Invalid default for #{name}"
          end
        end
      end

      def valid_default?(value, spec)
        case spec.fetch("type")
        when "number" then bounded_number?(value, spec)
        when "string" then value.is_a?(String)
        when "boolean" then boolean?(value)
        when "color" then value.is_a?(String) && COLOR.match?(value)
        when "enum" then spec.fetch("values").include?(value)
        when "point" then point?(value, spec)
        when "polygon" then value.is_a?(Array) && value.size >= 3 && value.all? { |point| point?(point, spec) }
        end
      end

      def point?(value, spec)
        value.is_a?(Array) && value.size == 2 && value.all? { |axis| bounded_number?(axis, spec) }
      end

      def bounded_number?(value, spec)
        number?(value) && (!spec.key?("min") || value >= spec["min"]) && (!spec.key?("max") || value <= spec["max"])
      end

      def number?(value) = value.is_a?(Numeric) && value.real? && value.finite?
      def boolean?(value) = value == true || value == false

      def json_schema(spec)
        type = spec.fetch("type")
        number = {"type" => "number"}
        number["minimum"] = spec["min"] if spec.key?("min")
        number["maximum"] = spec["max"] if spec.key?("max")
        point = {"type" => "array", "minItems" => 2, "maxItems" => 2, "items" => number}
        property = case type
        when "number" then number
        when "point" then point.merge("studio_type" => "point")
        when "polygon" then {"type" => "array", "minItems" => 3, "items" => point, "studio_type" => "polygon"}
        when "color" then {"type" => "string", "pattern" => "^#[0-9a-fA-F]{6}$", "studio_type" => "color"}
        when "enum" then {"enum" => spec.fetch("values"), "studio_type" => "enum"}
        else {"type" => type}
        end
        property.merge(spec.slice("default", "unit"))
      end
    end
  end
end
