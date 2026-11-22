# frozen_string_literal: true

module LightekTeam
  class NetworkMember < ApplicationRecord
    self.table_name = 'lightek_team_network_members'
    belongs_to :channel, class_name: 'LightekTeam::NetworkChannel'
    belongs_to :peer, class_name: 'LightekReservations::Peer'
  end
end
