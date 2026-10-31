module LightekPwa
  class Membership < ApplicationRecord
    self.table_name = "lightek_pwa_memberships"
    ROLES = %w[member moderator editor admin].freeze
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :profile
    validates :profile_id, uniqueness: {scope: :site_id}
    validates :role, inclusion: {in: ROLES}
    validates :status, inclusion: {in: %w[active suspended]}
  end
end
