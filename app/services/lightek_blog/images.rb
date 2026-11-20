# frozen_string_literal: true

module LightekBlog
  module Images
    TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    MAX_BYTES = 20.megabytes

    def self.uploads!(files, existing_count:)
      files = Array(files).reject(&:blank?)
      raise ArgumentError, "An article can have up to eight media files." if existing_count + files.length > 8

      files.map do |file|
        unless file.respond_to?(:tempfile) && file.respond_to?(:original_filename) && file.size.between?(1, MAX_BYTES)
          raise ArgumentError, "Choose image files up to 20 MB each."
        end

        io = file.tempfile
        content_type = Marcel::MimeType.for(io)
        io.rewind
        raise ArgumentError, "Choose JPEG, PNG, WebP, or GIF images." unless TYPES.include?(content_type)

        {io: io, filename: file.original_filename, content_type: content_type, identify: false}
      end
    end

    def self.for_entry(entry)
      entry.post.media_attachments.includes(:blob).select { |attachment| TYPES.include?(attachment.blob.content_type) }
    end

    def self.blob!(entry, id)
      blob = entry.post.media_attachments.find(id).blob
      raise ActiveRecord::RecordNotFound unless TYPES.include?(blob.content_type)

      blob
    end

    def self.deliver(controller, blob)
      controller.response.headers["Cache-Control"] = "private, no-store"
      controller.response.headers["Content-Disposition"] = "inline"
      controller.response.headers["Content-Length"] = blob.byte_size.to_s
      controller.content_type = blob.content_type
      controller.response_body = controller.request.head? ? [] : Enumerator.new { |out| blob.download { |chunk| out << chunk } }
    end
  end
end
