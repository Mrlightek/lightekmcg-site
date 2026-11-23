module LightekWorkspace
  class Drive < ApplicationRecord
    self.table_name = 'lightek_shared_drives'

    belongs_to :employer, class_name: 'User'
    has_many :members, class_name: 'LightekWorkspace::DriveMember'
    has_many :entries, class_name: 'LightekWorkspace::DriveEntry'
    def self.accessible_to(actor, employer)
      scope = where(employer: employer)
      return scope if actor.id == employer.id

      scope.where(id: LightekWorkspace::DriveMember.where(user: actor).select(:drive_id))
    end

    def editable_by?(actor)
      employer_id == actor.id || members.exists?(user: actor, role: 'editor')
    end

    validates :name, presence: true, length: {maximum: 120}
  end
end
