require_relative "../recipe_session"

module Studio
  module Operation
    class EngineAdapter
      attr_reader :engine, :executable

      def initialize(engine:, executable:)
        @engine = engine.to_s
        @executable = File.expand_path(executable) if executable && !executable.empty?
      end

      def self.configured
        RecipeSession::ADAPTERS.keys.to_h do |engine|
          [engine, new(engine: engine, executable: ENV["STUDIO_#{engine.upcase}_CLI"])]
        end
      end

      def cache_key = [self.class, engine, executable]
      def runnable? = executable && File.file?(executable) && File.executable?(executable)

      def available_commands
        RecipeSession.open(engine, executable, nil, total_timeout: 5) do |adapter, _session|
          adapter.available_commands
        end
      end
    end
  end
end
