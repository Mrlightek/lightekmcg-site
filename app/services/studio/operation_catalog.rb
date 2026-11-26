require "yaml"
require_relative "operation/engine_adapter"
require_relative "operation/thin"
require_relative "operation/thick"

module Studio
  class OperationCatalog
    class RegistryCache
      Snapshot = Data.define(:commands, :available, :refresh_after)
      MAX_ENTRIES = 32

      def initialize
        @snapshots = {}
        @lock = Mutex.new
      end

      def read(engine, adapter)
        return Snapshot.new(commands: {}, available: false, refresh_after: 0) unless adapter

        key = [engine, adapter.respond_to?(:cache_key) ? adapter.cache_key : adapter]
        @lock.synchronize do
          cached = @snapshots[key]
          if !adapter.runnable?
            return Snapshot.new(commands: cached&.commands || {}, available: false, refresh_after: 0)
          end

          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return cached if cached && now < cached.refresh_after

          begin
            commands = freeze_registry(adapter.available_commands)
            snapshot = Snapshot.new(commands: commands, available: true, refresh_after: now + 60)
          rescue RecipeSession::StepError, SystemCallError, IOError, Timeout::Error
            snapshot = Snapshot.new(commands: cached&.commands || {}, available: false, refresh_after: now + 5)
          end
          @snapshots.delete(key)
          @snapshots[key] = snapshot
          @snapshots.shift if @snapshots.length > MAX_ENTRIES
          snapshot
        end
      end

      private

      # A returned schema can be shared by catalog entries from multiple sites.
      def freeze_registry(value)
        case value
        when Hash then value.each_value { |entry| freeze_registry(entry) }
        when Array then value.each { |entry| freeze_registry(entry) }
        end
        value.freeze
      end
    end

    REGISTRIES = RegistryCache.new

    def self.for_site(site, engine_adapters: Operation::EngineAdapter.configured,
      built_in_directory: Rails.root.join("config/studio/operations"), command_schema_directory: nil,
      logger: default_logger, include_thin: true, match_display_names: true)
      new(site, engine_adapters, built_in_directory, command_schema_directory, logger).entries(
        include_thin: include_thin, match_display_names: match_display_names)
    end

    def self.find(site, id, origin: nil, surface: nil, engine_adapters: Operation::EngineAdapter.configured,
      built_in_directory: Rails.root.join("config/studio/operations"), command_schema_directory: nil,
      logger: default_logger)
      new(site, engine_adapters, built_in_directory, command_schema_directory, logger).find(id, origin: origin, surface: surface)
    end

    def self.default_logger
      Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
    end

    def initialize(site, engine_adapters, built_in_directory, command_schema_directory, logger)
      raise ArgumentError, "A persisted Studio site is required" unless site.is_a?(DymondSite::Site) && site.persisted?

      @site = site
      @adapters = engine_adapters.transform_keys(&:to_s)
      @built_in_directory = built_in_directory
      @command_schema_directory = command_schema_directory || File.join(File.dirname(built_in_directory), "command_schemas")
      @logger = logger
    end

    def entries(include_thin: true, match_display_names: true)
      visible_tenants = []
      tenant_operations.each do |candidate|
        visible_tenants << candidate unless visible_tenants.any? { |other| same_slot?(other, candidate, match_display_names) }
      end
      visible_built_ins = built_in_operations.reject do |builtin|
        visible_tenants.any? { |tenant| same_slot?(tenant, builtin, match_display_names) }
      end
      operations = (visible_built_ins + visible_tenants).sort_by { |operation| [operation.display_name.downcase, operation.id] }
      include_thin ? operations + thin_operations : operations
    end

    def find(id, origin: nil, surface: nil)
      candidates = if id.start_with?("studio.")
        case origin
        when :builtin then built_in_operations
        when :tenant then tenant_operations
        when nil then tenant_operations + built_in_operations
        else []
        end
      else
        origin.nil? ? thin_operations : []
      end
      matches = candidates.select { |entry| entry.id == id && (!surface || entry.surface.to_s == surface.to_s) }
      if matches.map(&:surface).uniq.size > 1
        raise ArgumentError, "Choose a surface for operation #{id}"
      end

      matches.first
    end

    private

    def built_in_operations
      @built_in_operations ||= Dir.glob(File.join(@built_in_directory, "*.y{a,}ml")).sort.map do |path|
        Operation::Thick.new(YAML.safe_load_file(path, aliases: false), engine_adapters: @adapters)
      rescue Psych::Exception, ArgumentError => error
        raise ArgumentError, "#{File.basename(path)}: #{error.message}"
      end
    end

    def tenant_operations
      @tenant_operations ||= OperationRecord.published.where(site_id: @site.id).order(version: :desc, id: :desc)
        .uniq { |record| [record.operation_id, record.surface] }
        .map do |record|
          record.operation(engine_adapters: @adapters, catalog_options: {
            engine_adapters: @adapters, built_in_directory: @built_in_directory,
            command_schema_directory: @command_schema_directory, logger: @logger
          })
        end
    end

    def same_slot?(first, second, match_display_names)
      first.surface == second.surface &&
        (first.id == second.id || (match_display_names && first.display_name.casecmp?(second.display_name)))
    end

    def thin_operations
      required = (built_in_operations + tenant_operations).group_by { |operation| operation.recipe.engine }
      Operation::Thin::SURFACES.keys.flat_map do |engine|
        adapter = @adapters[engine]
        registry = REGISTRIES.read(engine, adapter)
        metadata = Operation::CommandMetadata.load(@command_schema_directory, engine)
        if registry.available || !registry.commands.empty?
          unknown = metadata.keys - registry.commands.keys
          unless unknown.empty?
            raise ArgumentError, "#{engine}.yml: commands absent from registry: #{unknown.join(', ')}"
          end
        end

        known = required.fetch(engine, []).flat_map { |operation| operation.recipe.command_ids }
        entries = (known | registry.commands.keys).sort.map do |command_id|
          Operation::Thin.new(engine: engine, command_id: command_id,
            signature: registry.commands.fetch(command_id, {}), adapter: adapter,
            discovered: registry.available && registry.commands.key?(command_id), metadata: metadata[command_id])
        end
        untyped = entries.select { |entry| registry.commands.key?(entry.command_id) && !entry.typed }
        unless untyped.empty?
          sample = untyped.first(5).map(&:id).join(", ")
          @logger&.info("Studio command catalog: #{untyped.size} #{engine} commands lack typed metadata (for example #{sample})")
        end
        entries
      end
    end
  end
end
