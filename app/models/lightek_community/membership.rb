# frozen_string_literal: true
module LightekCommunity
  class Membership < ApplicationRecord
    self.table_name = "lightek_community_memberships"
    belongs_to :community
    belongs_to :profile
    validates :profile_id, uniqueness: { scope: :community_id }
    validates :role, inclusion: { in: %w[owner admin member] }
  end
end
