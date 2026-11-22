# frozen_string_literal: true

module LightekTeam
  class NetworkChannel < ApplicationRecord
    self.table_name = 'lightek_team_network_channels'
    belongs_to :host_peer, class_name: 'LightekReservations::Peer'
    belongs_to :partner_peer, class_name: 'LightekReservations::Peer'
    has_many :members, class_name: 'LightekTeam::NetworkMember', foreign_key: :channel_id
    has_many :messages, class_name: 'LightekTeam::NetworkMessage', foreign_key: :channel_id

    normalizes :name, with: ->(name) { name.strip.downcase }
    validates :name, length: {in: 2..60}, format: {with: /\A[a-z0-9][a-z0-9-]*\z/}
    validates :key, presence: true

    def other_peer(peer) = host_peer_id == peer.id ? partner_peer : host_peer
  end
end
