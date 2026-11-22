# frozen_string_literal: true

module LightekTeam
  class Membership < ApplicationRecord
    self.table_name = 'lightek_team_memberships'

    belongs_to :channel, class_name: 'LightekTeam::Channel'
    belongs_to :user
    validates :user_id, uniqueness: {scope: :channel_id}
  end
end
