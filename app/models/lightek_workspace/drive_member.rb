module LightekWorkspace
  class DriveMember < ApplicationRecord
    self.table_name = 'lightek_shared_drive_members'

    belongs_to :drive, class_name: 'LightekWorkspace::Drive'
    belongs_to :user
    validates :role, inclusion: {in: %w[viewer editor]}
  end
end
