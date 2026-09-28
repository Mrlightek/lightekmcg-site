require "fileutils"
require "json"
require "open3"
require "timeout"

module Blender
  class Runner
    Result = Data.define(:output_directory, :stdout, :stderr)

    def initialize(execution_record)
      @execution_record = execution_record
    end

    def call
      FileUtils.mkdir_p(output_directory)
      File.write(manifest_path, JSON.pretty_generate(execution_record.manifest))

      stdout = stderr = nil
      status = nil

      Timeout.timeout(timeout_seconds) do
        stdout, stderr, status = Open3.capture3(*command)
      end

      File.write(output_directory.join("blender.log"), stdout.to_s + stderr.to_s)
      raise ExecutionError, "Blender exited #{status.exitstatus}: #{stderr}" unless status.success?

      Result.new(output_directory:, stdout:, stderr:)
    rescue Timeout::Error
      raise ExecutionError, "Blender exceeded the #{timeout_seconds}-second limit"
    end

    private

    class ExecutionError < StandardError; end

    attr_reader :execution_record

    def command
      [
        ENV.fetch("BLENDER_BIN", "blender"),
        "--background",
        "--factory-startup",
        "--python", Rails.root.join("blender/runner.py").to_s,
        "--",
        manifest_path.to_s,
        output_directory.to_s
      ]
    end

    def output_directory
      @output_directory ||= Pathname(ENV.fetch("BLENDER_OUTPUT_ROOT", Rails.root.join("storage/blender_jobs"))).join(execution_namespace, execution_record.id.to_s)
    end

    def execution_namespace
      execution_record.class.name.underscore.pluralize
    end

    def manifest_path = output_directory.join("manifest.json")
    def timeout_seconds = ENV.fetch("BLENDER_TIMEOUT_SECONDS", 900).to_i
  end
end
