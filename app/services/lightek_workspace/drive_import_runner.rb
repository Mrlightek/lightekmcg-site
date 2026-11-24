require "stringio"

module LightekWorkspace
  class DriveImportRunner
    class Superseded < StandardError; end

    def initialize(run, token)
      @run = run
      @token = token
      @drive = run.drive
    end

    def perform
      claimed = @run.with_lock do
        next false unless @run.state == "queued" && @run.run_token == @token

        @run.update!(state: "running")
      end
      return unless claimed

      authorize!
      folders = {"" => @run.folder}
      @run.archive.blob.open do |archive|
        DriveArchive.open(archive.path) do |zip, paths|
          @run.items.each_with_index do |item, index|
            process(zip, paths.fetch(item.fetch("path")), item, index, folders)
          end
        end
      end
      @run.with_lock do
        ensure_current!
        @run.update!(state: "complete")
      end
      @run.archive.purge_later
    rescue ActiveRecord::RecordNotFound, Superseded
      nil
    rescue LightekPeople::Access::Denied
      fail_with("Drive editing access changed. The import stopped.")
    rescue ArgumentError => error
      fail_with(error.message)
    rescue StandardError => error
      Rails.logger.error("[LightekWorkspace] ZIP import #{@run.id} stopped: #{error.class}")
      fail_with("The import stopped before finishing. Retry to continue without copying saved files.")
    end

    private

    def process(zip, entry, item, index, folders)
      return if item.fetch("status") == "skipped"

      path = item.fetch("path")
      parent_path, name = DriveArchive.split(path)
      directory = item.fetch("type") == "folder"
      parent = folders.fetch(parent_path)
      blob = nil
      if parent == false
        result = ["conflict", nil, "Its parent folder could not be imported."]
      else
        bytes = DriveArchive.read(zip, entry) unless directory
        result = nil
      end

      @run.with_lock do
        ensure_current!
        unless result
          result = @drive.with_lock do
            authorize!
            save_entry(path, name, directory, parent, bytes) { |value| blob = value }
          end
        end
        status, saved, detail = result
        folders[path] = saved || false if directory
        @run.items[index] = item.merge("status" => status, "message" => detail)
        @run.save!
      end
    rescue StandardError
      blob&.delete if blob && !ActiveStorage::Blob.exists?(key: blob.key)
      raise
    end

    def save_entry(path, name, directory, parent, bytes)
      digest = directory ? "folder" : Digest::SHA256.hexdigest(bytes)
      receipt = DriveArchive.receipt_for(@drive, @run.folder, path)
      if receipt.persisted?
        if receipt.entry && receipt.digest == digest
          return ["duplicate", receipt.entry, "Already imported."]
        end
        return ["conflict", nil, "A previous import used this path with different content."]
      end

      existing = DriveArchive.child(@drive, parent, name)
      if existing == :ambiguous || (existing && (!directory || !existing.folder?))
        return ["conflict", nil, "An existing entry occupies this path."]
      end

      if directory
        entry = existing || @drive.entries.create!(parent: parent, creator: @run.actor, name: name, folder: true)
        status = existing ? "reuse" : "imported"
        detail = nil
      else
        attributes, detail = DriveArchive.office(bytes, name)
        entry = if attributes
          @drive.create_office_entry!(parent: parent, actor: @run.actor, attributes: attributes)
        else
          io = StringIO.new(bytes)
          blob = ActiveStorage::Blob.build_after_unfurling(io: io, filename: name, content_type: "application/octet-stream", identify: false)
          yield blob
          blob.save!
          blob.upload_without_unfurling(io)
          @drive.entries.create!(parent: parent, creator: @run.actor, name: name, folder: false, upload: blob)
        end
        status = "imported"
      end
      receipt.update!(entry: entry, digest: digest)
      [status, entry, detail]
    end

    def authorize!
      actor = @run.actor.reload
      DriveImport.authorize!(@drive, actor)
      if @run.folder_id
        @drive.entries.where(folder: true).find(@run.folder_id)
      end
    end

    def ensure_current!
      raise Superseded unless @run.run_token == @token && @run.state == "running"
    end

    def fail_with(message)
      @run.reload.with_lock do
        ensure_current!
        @run.update!(state: "failed", error_message: message.truncate(240))
      end
    rescue ActiveRecord::RecordNotFound, Superseded
      nil
    end
  end
end
