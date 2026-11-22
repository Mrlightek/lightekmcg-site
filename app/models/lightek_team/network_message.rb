# frozen_string_literal: true

module LightekTeam
  class NetworkMessage < ApplicationRecord
    self.table_name = 'lightek_team_network_messages'
    belongs_to :channel, class_name: 'LightekTeam::NetworkChannel'
    belongs_to :peer, class_name: 'LightekReservations::Peer'
    validates :body, presence: true, length: {maximum: 4_000}
  end
end
