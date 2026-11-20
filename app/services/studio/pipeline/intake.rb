# frozen_string_literal: true

require "digest"
require "pathname"

module Studio
  module Pipeline
    class Intake
      FORMATS = %w[.fbx .glb .gltf .unitypackage].freeze
      LIMIT = 150.megabytes
      MAX_SIDECARS = 48

      def initialize(access, file:, sidecars:, sidecar_paths:, mode:, target:, model_path:)
        @access, @file, @sidecars, @mode, @target = access, file, sidecars, mode, target
        @model_path = model_path.to_s.presence
        @extension = File.extname(file.original_filename).downcase if file.respond_to?(:tempfile)
        raise ArgumentError, "Choose an FBX, GLB, glTF or Unity package" unless FORMATS.include?(@extension)
        raise ArgumentError, "Unknown intake stage" unless %w[base props].include?(mode)
        raise ArgumentError, "Use a mesh export for Base Mesh" if @extension == ".unitypackage" && mode == "base"
        raise ArgumentError, "Enter a model path only for a Unity package" if @model_path && @extension != ".unitypackage"
        raise ArgumentError, "Model path is too long" if @model_path && @model_path.bytesize > 512
        raise ArgumentError, "Upload at most #{MAX_SIDECARS} sidecars" if sidecars.size > MAX_SIDECARS || sidecars.size != sidecar_paths.size
        raise ArgumentError, "Attach sidecars only for glTF or FBX" if sidecars.any? && !%w[.gltf .fbx].include?(@extension)
        raise ArgumentError, "Files must be nonempty and total at most 150 MB" unless
          [file, *sidecars].all? { |part| part.respond_to?(:tempfile) && part.size.positive? } &&
          [file, *sidecars].sum(&:size) <= LIMIT

        @paths = sidecar_paths.map { |path| self.class.relative_path(path) }
        raise ArgumentError, "Sidecar paths must be unique" unless @paths.uniq == @paths
        @filename = File.basename(file.original_filename.tr("\\", "/"))
        raise ArgumentError, "Invalid source filename" unless self.class.relative_path(@filename) == @filename && @filename.bytesize <= 200
        raise ArgumentError, "Sidecar path conflicts with source filename" if @paths.any? { |path| path.split("/").first == @filename }
      end

      def self.relative_path(path)
        raise ArgumentError, "Invalid asset path" unless path.is_a?(String) && path.bytesize.between?(1, 512) &&
          !path.match?(/[[:cntrl:]\\:]/) && path.split("/", -1).all? { |part| part.present? && !part.in?([".", ".."]) }
        path
      end

      def call
        fingerprint = Digest::SHA256.hexdigest(JSON.generate([
          @extension, @mode, @model_path, Digest::SHA256.file(@file.tempfile.path).hexdigest,
          @sidecars.zip(@paths).map { |file, path| [path, Digest::SHA256.file(file.tempfile.path).hexdigest] }.sort
        ]))
        version = nil
        @access.user.with_lock do
          if @target.present?
            card = @access.cards.lock.find(@target)
            stage = card.metadata["pipeline_stage"]
            if card.metadata["pipeline_digest"] == fingerprint && card.status != "failed"
              next card
            end
            if stage == "mixamo"
              raise ArgumentError, "Return a Mixamo FBX to this card" unless @extension == ".fbx" && @mode == "props"
              raise ArgumentError, "This card is already processing an export" if card.status.in?(%w[uploaded processing]) && !card.metadata["pipeline_prepared"]
            elsif !(stage == @mode && card.status == "failed")
              raise ArgumentError, "This card is not waiting for a replacement export"
            end
          else
            key = "pipeline:#{@access.site.id}:#{fingerprint}"
            card = @access.cards.find_or_initialize_by(owner: @access.user, request_key: key)
            next card if card.persisted? && card.status != "failed"
            stage = @mode
          end

          version = SecureRandom.uuid
          card.assign_attributes(owner: card.owner || @access.user, site: @access.site, kind: "glb",
            name: card.name.presence || File.basename(@filename, ".*").first(160),
            status: "uploaded", error_message: nil,
            metadata: card.metadata.to_h.merge("pipeline_stage" => stage, "pipeline_digest" => fingerprint,
              "pipeline_version" => version, "pipeline_actor" => @access.user.id, "pipeline_model_path" => @model_path,
              "pipeline_prepared" => false, "pipeline_source_name" => @filename, "pipeline_sidecar_paths" => @paths))
          card.file = { io: @file.tempfile, filename: @filename, content_type: "application/octet-stream", identify: false }
          card.pipeline_sidecars = @sidecars.each_with_index.map do |part, index|
            { io: part.tempfile, filename: format("%03d.bin", index), content_type: "application/octet-stream", identify: false }
          end
          card.save!
          card
        end.tap do |card|
          if version && !StudioPipelineAssetJob.perform_later(card.id, version)
            card.update!(status: "failed", error_message: "Could not queue conversion. Upload the export again.")
          end
        end
      end
    end
  end
end
