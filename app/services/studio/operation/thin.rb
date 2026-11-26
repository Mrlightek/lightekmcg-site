require_relative "command_metadata"

module Studio
  module Operation
    class Thin
      SURFACES = {"photocraft" => :image, "effectcraft" => :motion}.freeze
      INTERNAL_COMMANDS = /\A(?:app|cache|command|debug|engine|file|help|internal|jobs|journal|plugin|prefs|script|scriptui|session|storage|updates|window)\./

      attr_reader :accepts, :returns, :parameter_names, :command_id, :engine, :params_signature, :params_schema, :typed_params, :typed, :requires, :hidden

      def initialize(engine:, command_id:, signature:, adapter:, discovered:, metadata: nil)
        @engine = engine
        @command_id = command_id
        @params_signature = signature["params"]
        native = signature["schema"]
        @typed_params = metadata&.typed_params || {}
        @requires = metadata&.requires || []
        @params_schema = (metadata ? metadata.merge_schema(native) : native) || params_signature
        @typed = !!CommandMetadata.typed_schema?(@params_schema)
        properties = @params_schema.is_a?(Hash) ? @params_schema.fetch("properties", {}) : {}
        prose_names = params_signature.to_s.scan(/"([a-zA-Z][a-zA-Z0-9_]*)"\s*:/).flatten
        @parameter_names = (properties.keys | prose_names).freeze
        @accepts = HandleType.accepts(metadata&.accepts || {}, @parameter_names, verify_names: !signature.empty?)
        @returns = metadata&.returns || {}
        @adapter = adapter
        @discovered = discovered
        @hidden = INTERNAL_COMMANDS.match?(command_id)
      end

      def id = "#{engine}:#{command_id}"
      def display_name
        command_id.split(".").map do |segment|
          words = segment.gsub(/([A-Z])([A-Z][a-z])/, '\1 \2').gsub(/([a-z0-9])([A-Z])/, '\1 \2').tr("_", " ")
          words.sub(/\A./, &:upcase)
        end.join(" · ")
      end
      def surface = SURFACES.fetch(engine)
      def source = :thin
      def inputs_schema = {}
      def runnable? = @discovered && !!@adapter&.runnable?

      def native_type(name, _kind)
        return unless params_schema.is_a?(Hash)

        HandleType.from_schema(params_schema.dig("properties", name))
      end

      def result_path(name) = CommandResults.for(engine, command_id).fetch(name)

      def applicable?(context)
        requires.all? { |requirement| context.fetch(requirement) { context[requirement.to_s] } == true }
      end
    end
  end
end
