# frozen_string_literal: true

require "digest"
require "fileutils"

module Marlon
  module Blueprint
    class FileWriter
      def initialize(root: Rails.root, force: false)
        @root = Pathname(root)
        @force = force
      end

      def write(relative_path, content, blueprint_key:, artifact_type:)
        path = @root.join(relative_path)
        FileUtils.mkdir_p(path.dirname)

        if path.exist? && !@force
          raise Thor::Error, "Refusing to overwrite #{relative_path}; pass --force"
        end

        path.write(content)
        checksum = Digest::SHA256.hexdigest(content)

        Marlon::GeneratedArtifact.upsert(
          {
            blueprint_key: blueprint_key,
            artifact_type: artifact_type,
            path: relative_path.to_s,
            checksum: checksum,
            metadata: {},
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: %i[blueprint_key path]
        )

        relative_path
      end
    end
  end
end
