require_relative "../support/studio_recipe_fixture"
require "rbconfig"
require "tmpdir"
require "timeout"
require_relative "../../app/services/studio/recipe"

def assert(condition, message)
  raise message unless condition
end

def step_error(index:, command:, reason:, engine: "photocraft")
  yield
  raise "Expected #{reason} in #{command}"
rescue Studio::RecipeSession::StepError => error
  actual = [error.step_index, error.command, error.engine, error.reason]
  assert(actual == [index, command, engine, reason], "Wrong error fields: #{actual.inspect}: #{error.message}")
  error
end

definitions = File.expand_path("../../config/studio/recipes", __dir__)
character = StudioRecipeFixture.path
cases = {
  "photocraft" => ["add_facial_hair", character],
  "effectcraft" => ["animate_layer_position", nil]
}
cases.each do |engine, (name, source)|
  recipe = Studio::Recipe.load(File.join(definitions, "#{name}.json"))
  executable = File.expand_path(ENV.fetch("#{engine.upcase}_CLI"))
  Studio::RecipeSession.open(engine, executable, source) do |adapter, _session|
    registry = adapter.available_commands
    recipe.commands.each do |step|
      command = step.fetch("command")
      signature = registry.fetch(command)
      params = signature.fetch("params")
      assert(params.is_a?(String) && !params.empty?, "#{engine}: missing parameter signature for #{command}")
      step.fetch("params").each_key do |key|
        assert(params.match?(/\b#{Regexp.escape(key)}\b/), "#{engine}: #{command} signature omits #{key}: #{params}")
      end
      if engine == "effectcraft"
        assert(signature["schema"].is_a?(Hash), "EffectCraft did not return its command JSON Schema")
      end
    end
  end
end
puts "PASS both adapters report parameter signatures for every example command"

Dir.mktmpdir("studio-recipe-session-") do |directory|
  executable = File.join(directory, "engine")
  File.write(executable, "#!#{RbConfig.ruby} --disable-gems\n" + <<~'ENGINE')
    require "json"
    $stdout.sync = true
    $stderr.sync = true

    STDIN.each_line do |line|
      request = JSON.parse(line)
      command = request.dig("params", "command")
      result = {"pid" => Process.pid}
      case command
      when "test.wait"
        warn("α" * 1100 + "stderr tail")
        sleep
      when "test.malformed"
        puts "<malformed>"
        sleep
      when "test.dying"
        puts JSON.generate({"id" => request["id"], "ok" => true, "result" => result})
        warn "dying"
        exit! 7
      else
        puts JSON.generate({"id" => request["id"], "ok" => true, "result" => result})
      end
    end
  ENGINE
  File.chmod(0o700, executable)
  output = File.join(directory, "output.pcraft")
  baseline = {"name" => "Failures", "version" => 1, "engine" => "photocraft", "parameters" => {}}
  steps = [{"command" => "test.ok", "params" => {}}, {"command" => "test.wait", "params" => {}, "timeout" => 0.2}]
  recipe = Studio::Recipe.new(baseline.merge("steps" => steps))
  error = step_error(index: 1, command: "test.wait", reason: :timeout) do
    recipe.run!(executable: executable, input: character, output: output)
  end
  assert(error.message.include?("step exceeded 0.2 seconds"), error.message)
  assert(error.stderr == ("α" * 988 + "stderr tail\n"), "Incorrect stderr tail: #{error.stderr.length} characters")
  assert(!File.exist?(output), "Timed-out recipe published an output")

  steps.last["timeout"] = 3
  recipe = Studio::Recipe.new(baseline.merge("steps" => steps))
  error = step_error(index: 1, command: "test.wait", reason: :timeout) do
    recipe.run!(executable: executable, input: character, output: output, total_timeout: 0.4)
  end
  assert(error.message.include?("recipe ceiling exceeded"), error.message)
  assert(!File.exist?(output), "Recipe over its ceiling published an output")

  steps.last["command"] = "test.malformed"
  step_error(index: 1, command: "test.malformed", reason: :protocol_error) do
    Studio::Recipe.new(baseline.merge("steps" => steps)).run!(executable: executable, input: character, output: output)
  end
  assert(!File.exist?(output), "Protocol error published an output")

  error = step_error(index: 1, command: "test.wait", reason: :died) do
    Studio::RecipeSession.open("photocraft", executable, character, output) do |adapter, session|
      pid = session.step(step_index: 0, command: "test.ok") { adapter.execute("test.ok", {}).fetch("pid") }
      Process.kill("KILL", pid)
      Timeout.timeout(3) do
        loop do
          Process.kill(0, pid)
          sleep(0.01)
        rescue Errno::ESRCH
          break
        end
      end
      session.step(step_index: 1, command: "test.wait") { raise "Engine command was dispatched after death" }
    end
  end
  assert(error.message.include?("exited before dispatch"), error.message)
  assert(!File.exist?(output), "Dead engine published an output")
  steps = [{"command" => "test.dying", "params" => {}}, {"command" => "test.ok", "params" => {}}]
  step_error(index: 1, command: "test.ok", reason: :died) do
    Studio::Recipe.new(baseline.merge("steps" => steps)).run!(executable: executable, input: character, output: output)
  end
  assert(!File.exist?(output), "Recipe executor published an output after engine death")

  step_error(index: nil, command: "start", reason: :died) do
    Studio::RecipeSession.open("photocraft", File.join(directory, "missing-engine"), character) {}
  end
  steps.first["timeout"] = 0
  begin
    Studio::Recipe.new(baseline.merge("steps" => steps))
    raise "Expected invalid timeout validation"
  rescue ArgumentError => error
    assert(error.message == "Invalid timeout for test.dying", error.message)
  end
end
puts "PASS timeout, total ceiling, protocol error, pre-dispatch death, stderr tail and atomic output"
