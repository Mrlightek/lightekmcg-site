require "json"
require "open3"
require "timeout"
require_relative "recipe_protocol/photo_craft_session"
require_relative "recipe_protocol/effect_craft_session"

module Studio
  class RecipeSession
    DEFAULT_STEP_TIMEOUT = 30
    DEFAULT_TOTAL_TIMEOUT = 90
    ADAPTERS = {
      "photocraft" => RecipeProtocol::PhotoCraftSession,
      "effectcraft" => RecipeProtocol::EffectCraftSession
    }.freeze

    class ProtocolError < StandardError; end
    class StepDeadline < StandardError; end

    class StepError < StandardError
      attr_reader :step_index, :command, :engine, :reason, :stderr

      def initialize(step_index:, command:, engine:, reason:, stderr:, detail:)
        @step_index = step_index
        @command = command
        @engine = engine
        @reason = reason
        @stderr = stderr
        location = step_index.nil? ? command : "step #{step_index} (#{command})"
        super("#{engine} #{location}: #{reason} (#{detail})")
      end
    end

    def self.open(engine, executable, source, destination = nil, total_timeout: DEFAULT_TOTAL_TIMEOUT)
      raise ArgumentError, "Invalid recipe ceiling" unless valid_timeout?(total_timeout)

      adapter_class = ADAPTERS.fetch(engine)
      arguments = adapter_class.arguments(source, destination)
      spawned = false
      Open3.popen3([executable, executable], *arguments, pgroup: true) do |input, output, stderr, process|
        spawned = true
        session = new(engine, input, output, stderr, process, total_timeout)
        adapter = adapter_class.new(session)
        begin
          session.step(step_index: nil, command: "start") { adapter.start(source) }
          result = yield adapter, session
          session.step(step_index: nil, command: "shutdown") { session.finish }
          result
        ensure
          session.stop
        end
      end
    rescue SystemCallError => error
      raise if spawned

      raise StepError.new(step_index: nil, command: "start", engine: engine, reason: :died, stderr: "", detail: error.message)
    end

    def self.valid_timeout?(value)
      value.is_a?(Numeric) && value.real? && value.finite? && value.positive?
    end

    def initialize(engine, input, output, stderr, process, total_timeout)
      @engine = engine
      @input = input
      @output = output
      @stderr = stderr
      @process = process
      @deadline = monotonic_time + total_timeout
      @stderr_tail = +"".b
      @stderr_lock = Mutex.new
      @stderr_reader = Thread.new { drain_stderr }
    end

    def step(step_index:, command:, timeout: DEFAULT_STEP_TIMEOUT)
      unless @process.alive?
        fail_step(step_index, command, :died, "engine exited before dispatch")
      end

      remaining = @deadline - monotonic_time
      fail_step(step_index, command, :timeout, "recipe ceiling exceeded") unless remaining.positive?
      budget = [timeout, remaining].min
      Timeout.timeout(budget, StepDeadline) { yield }
    rescue StepDeadline
      detail = remaining <= timeout ? "recipe ceiling exceeded" : "step exceeded #{timeout} seconds"
      fail_step(step_index, command, :timeout, detail)
    rescue ProtocolError, JSON::ParserError, IOError, SystemCallError => error
      reason = @process.join(0.05) ? :died : :protocol_error
      fail_step(step_index, command, reason, error.message)
    end

    def write_json(message)
      @input.write(JSON.generate(message) << "\n")
      @input.flush
    end

    def read_json
      line = @output.gets
      raise ProtocolError, "engine closed stdout before replying" unless line

      JSON.parse(line)
    end

    def finish
      @input.close
      raise ProtocolError, "engine exited unsuccessfully" unless @process.value.success?
    end

    def stop
      return if @stopped

      begin
        # The leader may have exited while a child still holds the pipes open.
        Process.kill("KILL", -@process.pid)
      rescue Errno::ESRCH
        nil
      end
      unless @stderr_reader.join(0.25)
        @stderr.close
        @stderr_reader.join
      end
      @stopped = true
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def fail_step(step_index, command, reason, detail)
      stop
      stderr = @stderr_lock.synchronize { @stderr_tail.dup.force_encoding("UTF-8").scrub }
      raise StepError.new(step_index: step_index, command: command, engine: @engine,
        reason: reason, stderr: stderr[-1000..] || stderr, detail: detail)
    end

    def drain_stderr
      loop do
        chunk = @stderr.readpartial(4096)
        @stderr_lock.synchronize do
          @stderr_tail << chunk
          @stderr_tail = @stderr_tail.byteslice(-4000, 4000) || @stderr_tail
        end
      end
    rescue EOFError, IOError
      nil
    end
  end
end
