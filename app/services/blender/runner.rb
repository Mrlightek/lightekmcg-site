require "fileutils"
require "json"
require "open3"
require "timeout"

module Blender
  class Runner
    Result = Data.define(
      :output_directory,
      :stdout,
      :stderr,
      :generated_outputs
    )

    class ExecutionError < StandardError; end

    EXPECTED_OUTPUTS = {
      "blend" => "scene.blend",
      "glb" => "scene.glb",
      "preview" => "preview.png"
    }.freeze

    def initialize(execution_record)
      @execution_record = execution_record
    end

    def call
      prepare_output_directory
      write_manifest

      stdout = stderr = nil
      status = nil

      Timeout.timeout(timeout_seconds) do
        stdout, stderr, status = Open3.capture3(*command)
      end

      write_log(stdout, stderr)

      unless status.success?
        raise ExecutionError,
              "Studio Render Engine exited #{status.exitstatus}: #{stderr}"
      end

      result_payload = read_result_payload!

      unless result_payload["status"] == "succeeded"
        raise ExecutionError,
              result_payload["error"].presence ||
              "Studio Render Engine reported failure"
      end

      generated_outputs = validate_expected_outputs!

      Result.new(
        output_directory: output_directory,
        stdout: stdout,
        stderr: stderr,
        generated_outputs: generated_outputs
      )
    rescue Timeout::Error
      raise ExecutionError,
            "Studio Render Engine exceeded the #{timeout_seconds}-second limit"
    end

    private

    attr_reader :execution_record

    def prepare_output_directory
      FileUtils.mkdir_p(output_directory)
    end

    def write_manifest
      File.write(
        manifest_path,
        JSON.pretty_generate(execution_record.manifest)
      )
    end

    def write_log(stdout, stderr)
      File.write(
        output_directory.join("blender.log"),
        stdout.to_s + stderr.to_s
      )
    end

    def command
      [
        render_engine_binary,
        "--background",
        "--factory-startup",
        "--python",
        Rails.root.join("blender/runner.py").to_s,
        "--",
        manifest_path.to_s,
        output_directory.to_s
      ]
    end

    def render_engine_binary
      ENV["STUDIO_RENDER_ENGINE_BIN"].presence ||
        ENV["BLENDER_BIN"].presence ||
        "blender"
    end

    def output_directory
      @output_directory ||=
        Pathname(
          ENV.fetch(
            "BLENDER_OUTPUT_ROOT",
            Rails.root.join("storage/blender_jobs")
          )
        ).join(
          execution_namespace,
          execution_record.id.to_s
        )
    end

    def execution_namespace
      execution_record.class.name.underscore.pluralize
    end

    def manifest_path
      output_directory.join("manifest.json")
    end

    def result_path
      output_directory.join("render_result.json")
    end

    def read_result_payload!
      unless result_path.exist?
        raise ExecutionError,
              "Studio Render Engine did not produce render_result.json"
      end

      payload = JSON.parse(result_path.read)

      unless payload.is_a?(Hash)
        raise ExecutionError,
              "Studio Render Engine result payload is invalid"
      end

      payload
    rescue JSON::ParserError => error
      raise ExecutionError,
            "Studio Render Engine result payload could not be parsed: #{error.message}"
    end

    def validate_expected_outputs!
      requested = execution_record.manifest.fetch("outputs", {})

      unless requested.is_a?(Hash)
        raise ExecutionError,
              "Studio manifest outputs must be an object"
      end

      expected =
        EXPECTED_OUTPUTS.filter_map do |key, filename|
          filename if requested[key]
        end

      missing =
        expected.reject do |filename|
          path = output_directory.join(filename)
          path.exist? && path.size.positive?
        end

      if missing.any?
        raise ExecutionError,
              "Studio Render Engine did not produce required outputs: #{missing.join(', ')}"
      end

      expected
    end

    def timeout_seconds
      ENV.fetch(
        "STUDIO_RENDER_TIMEOUT_SECONDS",
        ENV.fetch("BLENDER_TIMEOUT_SECONDS", 900)
      ).to_i
    end
  end
end
