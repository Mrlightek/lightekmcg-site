module LightekIdentity
  class OrganizationPolicy < ApplicationRecord
    self.table_name = 'lightek_identity_organization_policies'
    belongs_to :employer, class_name: 'User'
    validates :employer_id, uniqueness: true
  end
end
