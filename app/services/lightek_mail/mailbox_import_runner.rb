require "stringio"

module LightekMail
  class MailboxImportRunner
    class Unavailable < StandardError; end
    class Superseded < StandardError; end

    def initialize(import, token)
      @import = import
      @token = token
    end

    def run
      claimed = @import.with_lock do
        next false unless @import.state == "queued" && @import.run_token == @token

        @import.update!(state: "running")
      end
      return unless claimed

      @account = @import.account
      @actor = @import.requested_by
      ensure_mailbox!
      @import.archive.blob.open do |io|
        MboxReader.each(io.binmode, offset: @import.byte_offset) { |entry| process(entry) }
      end
      @import.with_lock do
        ensure_current!
        @import.update!(state: @import.phase == "preview" ? "ready" : "complete")
      end
    rescue ActiveRecord::RecordNotFound, Superseded
      nil
    rescue MboxReader::InvalidArchive, Unavailable => error
      fail_with(error.message)
    rescue StandardError => error
      Rails.logger.error("[LightekMail] mailbox import #{@import.id} stopped: #{error.class}")
      fail_with("Processing stopped before finishing. Retry to continue from the saved checkpoint.")
    end

    private

    def process(entry)
      parsed, problem = parse_entry(entry)
      blobs = []
      @import.with_lock do
        ensure_current!
        column = @import.phase == "preview" ? :preview : :results
        counts = @import.public_send(column).deep_dup
        counts["messages"] = counts.fetch("messages", 0) + 1
        case
        when problem
          increment(counts, "invalid")
          samples = counts["errors"] ||= []
          samples << {"message" => counts["messages"], "reason" => problem} if samples.size < 10
        when column == :preview
          if parsed.duplicate?(@account.messages)
            increment(counts, "skipped")
          else
            counts["bytes"] = counts.fetch("bytes", 0) + parsed.attributes.fetch(:bytesize)
          end
        else
          outcome = @account.with_lock do
            ensure_mailbox!
            import_message(parsed, blobs)
          end
          increment(counts, outcome)
        end
        @import.update!(column => counts, byte_offset: entry.next_offset)
      end
    rescue StandardError
      blobs.each { |blob| blob.delete unless ActiveStorage::Blob.exists?(key: blob.key) }
      raise
    end

    def parse_entry(entry)
      [MboxMessage.new(entry), nil]
    rescue MboxMessage::InvalidMessage => error
      [nil, error.message]
    end

    def import_message(parsed, blobs)
      return "skipped" if parsed.duplicate?(@account.messages)

      attributes = parsed.attributes
      if @account.messages.sum(:bytesize) + attributes.fetch(:bytesize) > @account.storage_limit
        raise Unavailable, "Mailbox storage is full. Free space or increase the quota, then retry."
      end

      source = upload(parsed.raw, "original.eml", "message/rfc822", blobs)
      files = parsed.attachments.map { |file| upload(file.bytes, file.filename, file.content_type, blobs) }
      @account.messages.create!(attributes.merge(imported_at: Time.current, source: source, attachments: files))
      "imported"
    end

    # Upload synchronously so a saved message and its checkpoint always have
    # their original and attachments in storage when the transaction commits.
    def upload(bytes, filename, content_type, blobs)
      io = StringIO.new(bytes)
      blob = ActiveStorage::Blob.build_after_unfurling(io: io, filename: filename, content_type: content_type, identify: false)
      blobs << blob
      blob.save!
      blob.upload_without_unfurling(io)
      blob
    end

    def ensure_mailbox!
      unless @account.address == @import.mailbox_address && Access.accounts(@actor.reload).exists?(@account.id)
        raise Unavailable, "The destination mailbox changed or access was removed."
      end
    rescue Access::Denied
      raise Unavailable, "The destination mailbox changed or access was removed."
    end

    def ensure_current!
      raise Superseded unless @import.run_token == @token && @import.state == "running"
    end

    def increment(counts, key)
      counts[key] = counts.fetch(key, 0) + 1
    end

    def fail_with(text)
      @import.reload.with_lock do
        ensure_current!
        @import.update!(state: "failed", error_message: text)
      end
    rescue ActiveRecord::RecordNotFound, Superseded
      nil
    end
  end
end
