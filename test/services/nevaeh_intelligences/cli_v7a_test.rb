# frozen_string_literal: true
require "test_helper"
require "json"
require "stringio"
require "open3"
require "rbconfig"

class CliV7aTest < ActiveSupport::TestCase
  def invoke(*argv)
    out, err = StringIO.new, StringIO.new
    code = NevaehIntelligences::CliV7a.run(argv, out: out, err: err)
    [code, out.string, err.string]
  end

  def test_help_lists_documented_commands
    code, output, = invoke("help")
    assert_equal 0, code
    %w[help version doctor capabilities].each { |cmd| assert_includes output, cmd }
    assert_includes output, "--format json"
  end

  def test_json_doctor_has_no_execution_grants
    code, output, = invoke("--format", "json", "doctor")
    assert_equal 0, code
    data = JSON.parse(output)
    assert_equal true, data.fetch("ok")
    assert_equal false, data.dig("result", "dispatch_enabled")
    assert_equal false, data.dig("result", "production_execution_enabled")
    assert_equal false, data.dig("result", "rails_loaded")
  end

  def test_json_capabilities_are_explicitly_not_executable
    code, output, = invoke("--format", "json", "capabilities")
    assert_equal 0, code
    assert_equal false, JSON.parse(output).dig("result", "capability_execution_supported")
  end

  def test_unrecognized_command_is_rejected
    code, _, err = invoke("deploy")
    assert_equal 2, code
    assert_includes err, "unknown command"
  end

  def test_additional_arguments_are_rejected
    code, _, err = invoke("doctor", "production")
    assert_equal 2, code
    assert_includes err, "unexpected arguments"
  end

  def test_invalid_format_is_rejected
    code, _, err = invoke("--format", "yaml", "help")
    assert_equal 2, code
    assert_includes err, "invalid argument"
  end

  def test_executable_runs_without_booting_rails
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, Rails.root.join("bin/nevaeh").to_s, "--format", "json", "doctor", chdir: Rails.root.to_s)
    assert status.success?, stderr
    assert_equal false, JSON.parse(stdout).dig("result", "rails_loaded")
  end
end
