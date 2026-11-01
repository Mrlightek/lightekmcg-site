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
      "bundle" => "project.zip",
      "glb" => "scene.glb",
      "preview" => "preview.png"
    }.freeze

    def initialize(execution_record, asset_paths: {}, template_path: nil, template_bundle: nil)
      @execution_record = execution_record
      @asset_paths = asset_paths
      @template_path = template_path
      @template_bundle = template_bundle
    end

    def call
      prepare_output_directory
      write_manifest

      stdout = Studio::MediaProcess.run!(command, timeout: timeout_seconds, cancel_if: -> { execution_record.respond_to?(:status) && execution_record.reload.status == "cancelled" })
      write_log(stdout, "")

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
        stderr: "",
        generated_outputs: generated_outputs
      )
    rescue Timeout::Error
      raise ExecutionError,
            "Studio Render Engine exceeded the #{timeout_seconds}-second limit"
    rescue RuntimeError => error
      write_log(stdout, error.message)
      raise ExecutionError, error.message
    end

    private

    attr_reader :execution_record

    def prepare_output_directory
      FileUtils.mkdir_p(output_directory)
    end

    def write_manifest
      manifest=execution_record.manifest.deep_dup
      # Paths are supplied by the authorized provider, never by a client.
      manifest.delete("native_template_path")
      if @template_path
        path=output_directory.join("native-source.blend")
        if @template_bundle
          bundle=output_directory.join("native-bundle.zip")
          FileUtils.cp(@template_bundle,bundle)
          base=output_directory.join("native-bundle")
          Studio::MediaProcess.run!(["python3",Rails.root.join("blender/extract_demo.py").to_s,bundle.to_s,base.to_s],timeout:90)
          relative=manifest.dig("scene","settings","native_bundle_path").to_s
          candidate=base.join(relative).cleanpath
          raise ExecutionError,"Native bundle source path is invalid" if relative.empty? || Pathname(relative).absolute? || !candidate.to_s.start_with?(base.to_s+"/") || candidate.extname!=".blend"
          path=candidate
        end
        FileUtils.cp(@template_path,path)
        relative=path.relative_path_from(output_directory)
        manifest["native_template_path"]=Rails.env.production? ? "/work/#{relative}" : path.to_s
      elsif manifest.dig("scene","settings","native_blender_asset_id")
        raise ExecutionError,"Native Blender source was not resolved by the provider"
      end
      Array(manifest.dig("scene","objects")).each do |object|
        next unless object["type"]=="imported_asset"
        definition=object.fetch("definition")
        definition.delete("asset_path")
        next if definition["native_source_preview"]
        id=definition.fetch("asset_id").to_i
        entry=@asset_paths.fetch(id)
        entry={path:entry,format:"glb"} if entry.is_a?(String)
        path=output_directory.join("input-#{id}.#{entry.fetch(:format)}")
        FileUtils.cp(entry.fetch(:path),path)
        definition["asset_path"]=Rails.env.production? ? "/work/#{path.basename}" : path.to_s
        definition["asset_format"]=entry.fetch(:format)
        definition["asset_scene"]=entry[:scene]
      end
      File.write(manifest_path,JSON.pretty_generate(manifest))
    end

    def write_log(stdout, stderr)
      File.binwrite(
        output_directory.join("blender.log"),
        stdout.to_s.b + stderr.to_s.b
      )
    end

    def command
      script=Rails.root.join("blender/runner.py").to_s
      if Rails.env.production?
        image=ENV["STUDIO_RENDER_WORKER_IMAGE"].presence || ENV.fetch("STUDIO_ASSET_WORKER_IMAGE")
        ["docker","run","--rm","--name","lightek-render-#{SecureRandom.hex(8)}","--network","none","--read-only","--cap-drop","ALL","--security-opt","no-new-privileges","--pids-limit","256","--memory","4g","--cpus","2","--user","#{Process.uid}:#{Process.gid}","--tmpfs","/tmp:rw,nosuid,size=1g",
          "-v","#{output_directory}:/work:rw","-v","#{script}:/engine/runner.py:ro",image,"blender","--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python","/engine/runner.py","--","/work/manifest.json","/work"]
      else
        [render_engine_binary,"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",script,"--",manifest_path.to_s,output_directory.to_s]
      end
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
