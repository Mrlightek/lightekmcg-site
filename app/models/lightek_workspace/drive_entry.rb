module LightekWorkspace
  class DriveEntry < ApplicationRecord
    self.table_name = 'lightek_shared_drive_entries'

    belongs_to :drive, class_name: 'LightekWorkspace::Drive'
    belongs_to :creator, class_name: 'User'
    belongs_to :parent, class_name: name, optional: true
    has_one :office_file, class_name: 'LightekOffice::SharedFile', inverse_of: :drive_entry, autosave: true
    has_one_attached :upload
    validates :name, presence: true, length: {maximum: 160}
    validate :check_entry

    before_update :protect_upload, if: -> { attachment_changes.key?("upload") }
    before_destroy(prepend: true) { DiscoveryDriveHold.protect!(self, drive) }

    private

    def protect_upload
      DiscoveryDriveHold.protect!(self, drive) if upload_attachment_in_database?
    end

    def upload_attachment_in_database?
      ActiveStorage::Attachment.exists?(record: self, name: "upload")
    end

    def check_entry
      errors.add(:parent, 'must be a folder in this drive') if parent && (!parent.folder? || parent.drive_id != drive_id)
      if office_file
        errors.add(:base, 'An Office entry cannot be a folder or an upload') if folder? || upload.attached?
      elsif !folder? && (!upload.attached? || upload.blob.byte_size > 25.megabytes)
        errors.add(:upload, 'must be a file up to 25 MB')
      end
    end
  end
end
