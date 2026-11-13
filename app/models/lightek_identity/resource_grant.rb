module LightekIdentity
  class ResourceGrant < ApplicationRecord
    self.table_name = 'lightek_identity_resource_grants'
    belongs_to :employer, class_name: 'User'
    belongs_to :subject, polymorphic: true
    belongs_to :resource, polymorphic: true
    validates :subject_type, inclusion: {in: %w[LightekPeople::Employment LightekPeople::Department]}
    validates :resource_type, inclusion: {in: %w[GatekeeperNode GatekeeperHostedApplication]}
    validates :permission, inclusion: {in: %w[read manage login]}
    validate do
      errors.add(:subject, 'belongs to another employer') unless subject&.employer_id == employer_id
      owner = resource&.owner
      errors.add(:resource, 'belongs to another employer') unless owner.is_a?(User) && owner.id == employer_id
      errors.add(:permission, 'login is a server permission') if permission == 'login' && resource_type != 'GatekeeperNode'
    end
    after_save { DirectoryPolicy.changed!(employer_id) }
    after_destroy { DirectoryPolicy.changed!(employer_id) }
    after_commit { DirectorySyncJob.perform_later(employer_id) }
  end
end
