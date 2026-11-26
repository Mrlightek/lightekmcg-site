require "digest"
require "fileutils"
require "json"

module Studio
  module MacroMaker
    class EffectCraftExport
      MAX_ASSETS = 120
      MAX_BYTES = 100 * 1024 * 1024

      class MissingAssets < ArgumentError
        attr_reader :paths

        def initialize(paths)
          @paths = paths
          super("Missing EffectCraft files: #{paths.join(", ")}")
        end
      end

      def self.load(json)
        new(JSON.parse(json))
      rescue JSON::ParserError
        raise ArgumentError, "Export a valid EffectCraft project"
      end

      def initialize(project)
        @project = project
        items = project["items"] if project.is_a?(Hash)
        unless project.is_a?(Hash) && project["schema"] == 2 && items.is_a?(Hash)
          raise ArgumentError, "Export a valid EffectCraft project"
        end

        @footage = items.values.flat_map do |item|
          kind = item.is_a?(Hash) ? item["kind"] : nil
          unless kind.is_a?(Hash) && %w[Comp Solid Folder Footage].include?(kind["type"])
            raise ArgumentError, "Export a valid EffectCraft project"
          end
          proxy = item["proxy"]
          unless proxy.nil? || (proxy.is_a?(Hash) && proxy["footage"].is_a?(Hash))
            raise ArgumentError, "Export a valid EffectCraft proxy"
          end
          [(kind if kind["type"] == "Footage"), proxy&.fetch("footage")].compact
        end
        @footage.each do |footage|
          path = footage["path"]
          frames = footage.fetch("sequence", [])
          unless valid_path?(path, empty: embedded?(footage)) && frames.is_a?(Array) && frames.all? { |frame| valid_path?(frame) }
            raise ArgumentError, "Export valid EffectCraft footage links"
          end
          if footage["kind"] == "Model"
            raise ArgumentError, "3D model dependencies are unsupported: #{path}"
          end
        end
      end

      def validate_assets!(paths, uploads)
        unless paths.is_a?(Array) && uploads.is_a?(Array) && paths.size == uploads.size && paths.uniq == paths &&
            paths.all? { |path| valid_path?(path) } && paths.size <= MAX_ASSETS &&
            uploads.all? { |file| file.is_a?(ActionDispatch::Http::UploadedFile) && file.size.positive? } &&
            uploads.sum(&:size) <= MAX_BYTES
          raise ArgumentError, "Attach up to #{MAX_ASSETS} EffectCraft files totaling 100 MiB with one path per file"
        end

        missing = dependencies - paths
        raise MissingAssets.new(missing) if missing.any?
        raise ArgumentError, "Only attach files referenced by this EffectCraft project" if (paths - dependencies).any?
      end

      def dependencies
        @footage.flat_map do |footage|
          frames = footage.fetch("sequence", [])
          embedded?(footage) ? frames : [footage.fetch("path"), *frames]
        end.uniq
      end

      def stage!(destination, files, paths)
        raise MissingAssets.new(dependencies - paths) if (dependencies - paths).any?
        mapping = paths.each_with_index.to_h do |path, index|
          basename = safe_basename(path)
          relative = File.join("media", Digest::SHA256.hexdigest(path), basename)
          target = File.join(File.dirname(destination), relative)
          FileUtils.mkdir_p(File.dirname(target))
          attachment = files.fetch("asset-#{index}")
          File.open(target, "wb") { |file| attachment.download { |chunk| file.write(chunk) } }
          [path, relative]
        end
        reverse = mapping.invert
        # Embedded data is already in the project. Give its display path a local alias.
        @footage.select { |footage| embedded?(footage) }.map { |footage| footage["path"] }.uniq.each do |path|
          next if path.empty? || mapping.key?(path)

          alias_path = "inline-data/#{Digest::SHA256.hexdigest(path)}/#{safe_basename(path)}"
          mapping[path] = alias_path
          reverse[alias_path] = path
        end
        remap!(mapping) { |path| path }
        File.write(destination, JSON.generate(@project))
        reverse
      end

      def restore!(destination, reverse, job_directory)
        remap!(reverse) { |path| path.delete_prefix("#{job_directory}/") }
        File.write(destination, JSON.generate(@project))
      end

      private

      def embedded?(footage) = footage["kind"] == "Data" && footage["data"].is_a?(String)

      def safe_basename(path)
        name = File.basename(path.tr("\\", "/"))
        return name if name.bytesize <= 240 && !name.empty? && !%w[. .. /].include?(name)

        "media#{File.extname(name)[/\A\.[a-z0-9]{1,10}\z/i]}"
      end

      def valid_path?(path, empty: false)
        path.is_a?(String) && (empty || !path.empty?) && path.bytesize <= 1024 && !path.match?(/[[:cntrl:]]/)
      end

      def remap!(mapping)
        @footage.each do |footage|
          key = yield footage.fetch("path")
          footage["path"] = mapping.fetch(key, footage["path"])
          if footage.key?("sequence")
            footage["sequence"].map! { |path| mapping.fetch(yield(path), path) }
          end
        end
      end
    end
  end
end
