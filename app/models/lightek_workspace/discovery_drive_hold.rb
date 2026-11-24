module LightekWorkspace
  class DiscoveryDriveHold < ApplicationRecord
    self.table_name = "lightek_discovery_drive_holds"

    belongs_to :matter, class_name: "LightekMail::Matter", inverse_of: :drive_holds
    belongs_to :drive

    scope :active, -> { where(released_at: nil) }

    def self.protect!(record, drive)
      return unless drive

      drive.with_lock do
        if active.exists?(drive: drive)
          record.errors.add(:base, "This Shared Drive is on a discovery hold.")
          throw :abort
        end
      end
    end
  end
end
