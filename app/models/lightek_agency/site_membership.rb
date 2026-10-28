# frozen_string_literal: true
module LightekAgency
  class SiteMembership < ApplicationRecord
    self.table_name = "lightek_agency_site_memberships"
    belongs_to :site, class_name: "DymondSite::Site"
    belongs_to :user
    belongs_to :granted_by, class_name: "User"
    validates :role, inclusion: {in: %w[marketer designer manager]}
    validates :user_id, uniqueness: {scope: :site_id}
  end
end
