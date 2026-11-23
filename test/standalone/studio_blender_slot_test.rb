require "minitest/autorun"
require "pathname"
require "active_support/core_ext/string/access"
require_relative "../../app/services/studio/media_process"
require_relative "../../app/services/studio/compute/cpu_profile"

module Rails
  def self.root = Pathname(__dir__).join("../..").expand_path
end

class StudioBlenderSlotTest < Minitest::Test
  PROCESS = Studio::MediaProcess
  CONTAINER_ID = "a" * 64

  def test_launch_uses_a_daemon_wide_slot_and_bounded_memory
    with_worker do |read_calls|
      assert_equal "rendered", PROCESS.run!(blender_command)
      calls = read_calls.call
      run = calls.find { |args| args.first == "run" }
      assert_equal "lightek-blender-slot", run.fetch(run.index("--name") + 1)
      assert_equal "896m", run.fetch(run.index("--memory") + 1)
      assert_equal "896m", run.fetch(run.index("--memory-swap") + 1)
      label = run.fetch(run.index("--label") + 1)
      assert_includes calls, ["ps", "-aq", "--no-trunc", "--filter", "label=#{label}"]
      assert_includes calls, ["rm", "-f", CONTAINER_ID]
    end
  end

  def test_contention_only_checks_for_the_new_attempts_container
    with_worker(result: "conflict") do |read_calls|
      assert_raises(Studio::Compute::CpuProfile::Busy) { PROCESS.run!(blender_command) }
      calls = read_calls.call
      assert calls.any? { |args| args.first == "ps" }
      refute calls.any? { |args| args.first == "rm" }
    end
  end

  def test_a_detached_workstation_owns_the_slot_until_it_stops
    with_worker do |read_calls|
      PROCESS.run!(%w[docker run -d --name desktop --memory 4g workstation],
        cleanup_container: false, blender_workstation: true)
      calls = read_calls.call
      assert_equal ["run"], calls.map(&:first)
      assert_includes calls.first, "lightek-blender-slot"
    end
  end

  def test_insufficient_capacity_never_starts_a_container
    with_worker(result: "capacity") do |read_calls|
      error = assert_raises(PROCESS::BlenderCapacity) { PROCESS.run!(blender_command) }
      assert_match(/insufficient RAM/, error.message)
      assert_empty read_calls.call
    end
  end

  private

  def blender_command
    %w[docker run --name preview --memory 2g studio-image blender --background]
  end

  def with_worker(result: "ok")
    Dir.mktmpdir do |root|
      File.write(File.join(root, "python3"), <<~SH, perm: 0o700)
        #!/bin/sh
        if [ "$BLENDER_TEST_RESULT" = 'capacity' ]; then
          echo 'This server has insufficient RAM for Blender.' >&2
          exit 75
        fi
        printf '896m\\n'
      SH
      File.write(File.join(root, "docker"), <<~SH, perm: 0o700)
        #!/bin/sh
        printf '%s\\n' "$*" >> "$BLENDER_TEST_CALLS"
        case "$1:$BLENDER_TEST_RESULT" in
          run:conflict) echo 'Conflict. The container name lightek-blender-slot is already in use.' >&2; exit 125 ;;
          run:ok) printf rendered ;;
          ps:ok) printf '#{CONTAINER_ID}\\n' ;;
        esac
        exit 0
      SH
      original_path = ENV.fetch("PATH")
      ENV["PATH"] = "#{root}:#{original_path}"
      ENV["BLENDER_TEST_CALLS"] = File.join(root, "calls")
      ENV["BLENDER_TEST_RESULT"] = result
      FileUtils.touch(ENV.fetch("BLENDER_TEST_CALLS"))
      yield -> { File.readlines(ENV.fetch("BLENDER_TEST_CALLS"), chomp: true).map(&:split) }
    ensure
      ENV["PATH"] = original_path
      ENV.delete("BLENDER_TEST_CALLS")
      ENV.delete("BLENDER_TEST_RESULT")
    end
  end
end
