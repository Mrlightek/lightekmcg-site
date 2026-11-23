require "digest"
require "zip"

module LightekMail
  module DiscoveryExport
    MAX_BYTES = 50.megabytes
    module_function

    def build(matches, matter:, mailbox:)
      if matches.size > DiscoverySearch::LIMIT
        raise ArgumentError, "Narrow the search to at most #{DiscoverySearch::LIMIT} messages before exporting."
      end

      bytes = 0
      manifest = {matter_id: matter.id, mailbox: mailbox, exported_at: Time.current.iso8601, messages: []}
      archive = Zip::OutputStream.write_buffer do |zip|
        matches.each do |match|
          message = match.message.class.find(match.message.id)
          original_id = match.retained ? message.original_id : message.id
          prefix = "messages/#{original_id}"
          fields = match.retained ? message.snapshot : message.attributes.slice(*RetainedMessage::SNAPSHOT_FIELDS)
          metadata = fields.merge(subject: message.subject, from_address: message.from_address, text_body: message.text_body,
            sent_or_received_at: match.timestamp.iso8601, retained: match.retained).to_json
          bytes = reserve(bytes, metadata.bytesize)
          zip.put_next_entry("#{prefix}/message.json")
          zip.write(metadata)
          files = []
          if message.source.attached?
            bytes = reserve(bytes, message.source.byte_size)
            files << write_blob(zip, "#{prefix}/message.eml", message.source.blob)
          end
          message.attachments.each_with_index do |attachment, index|
            bytes = reserve(bytes, attachment.byte_size)
            extension = File.extname(attachment.filename.to_s)[/\A\.[a-zA-Z0-9]{1,12}\z/]
            files << write_blob(zip, "#{prefix}/attachment-#{index + 1}#{extension}", attachment.blob)
          end
          manifest[:messages] << {id: original_id, metadata_path: "#{prefix}/message.json",
            metadata_sha256: Digest::SHA256.hexdigest(metadata), files: files}
        end
        json = JSON.pretty_generate(manifest)
        reserve(bytes, json.bytesize)
        zip.put_next_entry("manifest.json")
        zip.write(json)
      end
      archive.string
    rescue ActiveStorage::FileNotFoundError
      raise ArgumentError, "A source file could not be read. No export was produced."
    end

    def reserve(bytes, size)
      total = bytes + size
      raise ArgumentError, "Narrow the search. An export is limited to 50 MB of data." if total > MAX_BYTES

      total
    end

    def write_blob(zip, path, blob)
      digest = Digest::SHA256.new
      bytes = 0
      zip.put_next_entry(path)
      blob.download do |chunk|
        bytes += chunk.bytesize
        raise ArgumentError, "A source file has an unexpected size. No export was produced." if bytes > blob.byte_size

        digest.update(chunk)
        zip.write(chunk)
      end
      unless bytes == blob.byte_size
        raise ArgumentError, "A source file could not be read completely. No export was produced."
      end

      {path: path, filename: blob.filename.to_s, content_type: blob.content_type, sha256: digest.hexdigest}
    end
  end
end
