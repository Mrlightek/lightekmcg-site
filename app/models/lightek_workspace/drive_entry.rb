module LightekWorkspace
  class DriveEntry < ApplicationRecord
    self.table_name = 'lightek_shared_drive_entries'

    belongs_to :drive, class_name: 'LightekWorkspace::Drive'
    belongs_to :creator, class_name: 'User'
    belongs_to :parent, class_name: name, optional: true
    has_one_attached :upload
    validates :name, presence: true, length: {maximum: 160}
    validate :check_entry

    private

    def check_entry
      errors.add(:parent, 'must be a folder in this drive') if parent && (!parent.folder? || parent.drive_id != drive_id)
      if !folder? && (!upload.attached? || upload.blob.byte_size > 25.megabytes)
        errors.add(:upload, 'must be a file up to 25 MB')
      end
    end
  end
end
