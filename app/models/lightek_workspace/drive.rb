module LightekWorkspace
  class Drive < ApplicationRecord
    self.table_name = 'lightek_shared_drives'

    belongs_to :employer, class_name: 'User'
    has_many :members, class_name: 'LightekWorkspace::DriveMember'
    has_many :entries, class_name: 'LightekWorkspace::DriveEntry'
    validates :name, presence: true, length: {maximum: 120}
  end
end
