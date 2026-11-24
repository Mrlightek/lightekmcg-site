module LightekMail
  class MailboxImport < ApplicationRecord
    self.table_name = "lightek_mail_imports"

    MAX_ARCHIVE_BYTES = 512.megabytes
    CLAIM_TIMEOUT = 20.minutes
    BUSY_STATES = %w[queued running].freeze

    belongs_to :account, class_name: "LightekMail::Account"
    belongs_to :requested_by, class_name: "User"
    belongs_to :team_mailbox, class_name: "LightekMail::TeamMigrationMailbox", optional: true, inverse_of: :mailbox_import
    has_one_attached :archive

    scope :in_mailbox, ->(account) { where(account_id: account.id, mailbox_address: account.address) }

    def self.create_upload!(account, actor, upload, team_mailbox: nil)
      unless upload.respond_to?(:tempfile) && File.extname(upload.original_filename).casecmp?(".mbox") &&
          upload.size.between?(1, MAX_ARCHIVE_BYTES)
        raise ArgumentError, "Choose an uncompressed .mbox file up to 512 MB."
      end

      team_mailbox&.authorize_upload!(actor, account)
      address = account.address
      bytes = upload.size
      validate_archive_space!(account, bytes)
      blob = ActiveStorage::Blob.create_and_upload!(io: upload.tempfile, filename: upload.original_filename,
        content_type: "application/mbox", identify: false)
      import = account.with_lock do
        raise ArgumentError, "The destination mailbox changed during the upload." unless account.address == address

        if team_mailbox
          team_mailbox.authorize_upload!(actor, account)
          raise ArgumentError, "Remove the existing archive before uploading another." if exists?(team_mailbox: team_mailbox)
        end
        validate_archive_space!(account, blob.byte_size)
        state = team_mailbox&.requires_approval? ? "awaiting_approval" : "queued"
        create!(account: account, requested_by: actor, mailbox_address: address, team_mailbox: team_mailbox, state: state,
          archive: blob, archive_bytes: blob.byte_size, run_token: SecureRandom.uuid)
      end
      import.enqueue if import.state == "queued"
      import
    rescue StandardError
      blob&.purge unless import&.persisted?
      raise
    end

    def self.validate_archive_space!(account, bytes)
      if in_mailbox(account).sum(:archive_bytes) + bytes > MAX_ARCHIVE_BYTES
        raise ArgumentError, "This mailbox has reached 512 MB of import archives. Remove a finished archive, then upload again."
      end
    end
    private_class_method :validate_archive_space!

    def approve_team_archive!(actor)
      with_lock do
        unless state == "awaiting_approval" && team_mailbox && actor.id == team_mailbox.mailbox_user_id &&
            account.user_id == actor.id && Access.accounts(actor).exists?(account_id)
          raise Access::Denied, "Only the mapped mailbox owner can approve this archive."
        end

        team_mailbox.authorize_upload!(requested_by)
        update!(approved_at: Time.current, state: "queued", run_token: SecureRandom.uuid)
      end
      enqueue
    end

    def start_import!
      with_lock do
        unless importable? || (state == "complete" && readable_preview?)
          raise ArgumentError, "Preview a mailbox with at least one readable message first."
        end

        update!(phase: "import", state: "queued", run_token: SecureRandom.uuid, byte_offset: 0, results: {}, error_message: nil)
      end
      enqueue
    end

    def importable?
      state == "ready" && readable_preview?
    end

    def readable_preview?
      preview.fetch("messages", 0) > preview.fetch("invalid", 0)
    end

    def retry!
      with_lock do
        raise ArgumentError, "This import is still in progress." unless retryable?

        update!(state: "queued", run_token: SecureRandom.uuid, error_message: nil)
      end
      enqueue
    end

    def retryable?
      state == "failed" || (BUSY_STATES.include?(state) && updated_at <= CLAIM_TIMEOUT.ago)
    end

    def remove!
      with_lock do
        raise ArgumentError, "Wait for the active import before removing the archive." if BUSY_STATES.include?(state) && !retryable?

        destroy!
      end
    end

    def enqueue
      token = run_token
      return if MailboxImportJob.perform_later(id, token)

      with_lock do
        if state == "queued" && run_token == token
          update!(state: "failed", error_message: "The job could not be queued. Retry this import.")
        end
      end
    end
  end
end
