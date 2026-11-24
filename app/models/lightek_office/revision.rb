module LightekOffice
  class Revision < ApplicationRecord
    self.table_name = 'lightek_office_revisions'

    belongs_to :file, polymorphic: true

    before_update :protect_drive_revision
    before_destroy :protect_drive_revision

    private

    def protect_drive_revision
      if file.is_a?(SharedFile)
        LightekWorkspace::DiscoveryDriveHold.protect!(self, file.drive_entry&.drive)
      end
    end
  end
end
