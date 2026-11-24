module LightekWorkspace
  class DriveImportReceipt < ApplicationRecord
    self.table_name = "lightek_shared_drive_import_receipts"

    belongs_to :drive
    belongs_to :entry, class_name: "LightekWorkspace::DriveEntry", optional: true
  end
end
