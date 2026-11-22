# frozen_string_literal: true

module LightekTeam
  class PartnerMembership < ApplicationRecord
    self.table_name = 'lightek_team_partner_memberships'

    belongs_to :partnership, class_name: 'LightekTeam::Partnership'
    belongs_to :user
  end
end
