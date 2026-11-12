# frozen_string_literal: true
module Studio
  module Editors
    class Document
      MAX_BYTES = 24.megabytes
      KINDS = %w[photo video].freeze
      def initialize(scene:, actor:, kind:)
        @scene, @actor, @kind = scene, actor, kind
        raise ArgumentError, "Choose Photo or Video" unless KINDS.include?(kind)
        @access = Studio::PwaAccess.new("user_id" => actor.id, "site_id" => scene.studio_project.site_id)
        @access.scene!(scene.id)
        raise ArgumentError, "Open this production in its original editor" if scene.settings["editor_kind"].present? && scene.settings["editor_kind"] != kind
      end
      def load
        return nil unless @scene.editor_source.attached?
        JSON.parse(@scene.editor_source.download)
      end
      def save!(document:, lock_version:)
        normalized = normalize(document)
        data = JSON.generate(normalized)
        source_blob_id = nil
        @scene.with_lock do
          raise ActiveRecord::StaleObjectError.new(@scene, "save") unless @scene.lock_version == Integer(lock_version)
          @scene.editor_source.attach(io: StringIO.new(data), filename: "#{@kind}-project.json", content_type: "application/json")
          @scene.update!(settings: @scene.settings.merge("editor_kind" => @kind))
          source_blob_id = @scene.editor_source.blob.id
        end
        # ActiveStorage touches its owner on commit. Return that committed
        # revision, rather than making the next export look like a stale tab.
        @scene.reload
        raise ActiveRecord::StaleObjectError.new(@scene, "save") unless @scene.editor_source.blob.id == source_blob_id
        normalized
      end
      def normalize(document)
        raise ArgumentError, "Project must be an object" unless document.is_a?(Hash)
        raise ArgumentError, "Project is larger than 24 MB" if document.to_json.bytesize > MAX_BYTES
        document = document.deep_stringify_keys.deep_dup
        safe_keys!(document)
        @kind == "photo" ? photo(document) : video(document)
      end
      def safe_keys!(value, depth = 0)
        raise ArgumentError, "Project nesting is too deep" if depth > 30
        case value
        when Hash
          value.each do |key, child|
            raise ArgumentError, "Invalid project property" if %w[__proto__ constructor prototype].include?(key)
            safe_keys!(child, depth + 1)
          end
        when Array then value.each { |child| safe_keys!(child, depth + 1) }
        end
      end
      def video(document)
        mash = document.fetch("mash")
        raise ArgumentError, "Invalid video project" unless mash.is_a?(Hash)
        width, height = Integer(mash.fetch("width", 1280)), Integer(mash.fetch("height", 720))
        fps = Integer(mash.fetch("quantize", 30))
        raise ArgumentError, "Choose dimensions up to 1920 pixels and 1–60 fps" unless [width, height].all? { |v| (16..1920).cover?(v) } && (1..60).cover?(fps)
        tracks = mash.fetch("tracks", [])
        raise ArgumentError, "Use at most 16 tracks" unless tracks.is_a?(Array) && tracks.size <= 16
        clips = tracks.flat_map { |track| track.fetch("clips", []) }
        raise ArgumentError, "Use at most 128 clips" unless clips.size <= 128
        clips.each do |clip|
          frames, frame = Float(clip.fetch("frames", 0)), Float(clip.fetch("frame", 0))
          raise ArgumentError, "Clips must fit within a ten minute production" unless frames.finite? && frame.finite? && frames > 0 && frame >= 0 && frame + frames <= fps * 600
        end
        # The renderer receives only upstream built-in effects and media owned by
        # this actor/site. Never persist arbitrary file/network/filter definitions.
        reject_sources!(mash)
        definitions = Array(document["definitions"]).filter_map do |definition|
          id = definition.fetch("id").to_s
          next if id.start_with?("com.moviemasher.")
          match = /\Alightek\.media\.(\d+)\z/.match(id)
          raise ArgumentError, "Import media through Lightek before saving" unless match
          asset = StudioAsset.for_actor(@access).where(site_id: @access.site_id).find(match[1])
          raise ArgumentError, "Unsupported media" unless %w[image video audio].include?(asset.kind) && asset.file.attached?
          dimension = definition.slice("width", "height", "duration", "previewSize", "audio")
          %w[width height duration].each do |key|
            next unless dimension[key]
            value = Float(dimension[key])
            raise ArgumentError, "Invalid media dimensions or duration" unless value.finite? && value > 0 && value <= (key == "duration" ? 36000 : 32768)
          end
          url = "/dashboard/studio-broadcasting/assets/#{asset.id}/original?site_id=#{@access.site_id}"
          dimension.merge("id" => id, "type" => asset.kind, "label" => asset.name, "url" => url, "source" => url, "audioUrl" => url)
        end
        media_ids = mash.to_json.scan(/lightek\.media\.\d+/).uniq
        raise ArgumentError, "A clip's source media is missing" unless (media_ids - definitions.map { |definition| definition["id"] }).empty?
        {"mash" => mash.merge("width" => width, "height" => height, "quantize" => fps), "definitions" => definitions.uniq { |definition| definition["id"] }}
      end
      def reject_sources!(value, depth = 0)
        raise ArgumentError, "Project nesting is too deep" if depth > 30
        case value
        when Hash
          value.each do |key, child|
            raise ArgumentError, "Custom sources and executable filters are not supported" if %w[url source src audioUrl icon filters ffmpegFilter command commands inputs options code].include?(key)
            if key == "id"
              raise ArgumentError, "Invalid project element ID" unless child.is_a?(String) && child.match?(/\A[a-zA-Z0-9_-][a-zA-Z0-9_.-]{0,159}\z/)
            end
            if key.end_with?("Id") && child.is_a?(String)
              raise ArgumentError, "Unknown media or effect" unless child.match?(/\A(?:com\.moviemasher\.[a-zA-Z0-9_.-]+|lightek\.media\.\d+)\z/)
            end
            reject_sources!(child, depth + 1)
          end
        when Array then value.each { |child| reject_sources!(child, depth + 1) }
        when Float then raise ArgumentError, "Invalid number" unless value.finite?
        end
      end
      def photo(document)
        info = document.fetch("info")
        raise ArgumentError, "Photo dimensions must be between 1 and 4096 pixels" unless %w[width height].all? { |key| (1..4096).cover?(Integer(info.fetch(key))) }
        raise ArgumentError, "Use at most 100 layers" unless document.fetch("layers").is_a?(Array) && document["layers"].size <= 100
        raise ArgumentError, "Use installed fonts" if document.fetch("user_fonts", {}).present?
        Array(document["data"]).each do |image|
          raise ArgumentError, "Project images must be embedded" unless image.fetch("data").match?(/\Adata:image\/(png|jpeg|webp);base64,[A-Za-z0-9+\/=\s]+\z/)
        end
        document
      end
    end
  end
end
