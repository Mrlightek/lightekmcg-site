module LightekIdentity
  class NodeBinding < ApplicationRecord
    self.table_name = 'lightek_identity_node_bindings'
    belongs_to :realm
    belongs_to :gatekeeper_node
    validates :gatekeeper_node_id, uniqueness: true
    validate do
      errors.add(:gatekeeper_node, 'must be a remote server owned by this employer') unless gatekeeper_node.owner_type == 'User' && gatekeeper_node.owner_id == realm.employer_id && !gatekeeper_node.local?
    end
  end
end
