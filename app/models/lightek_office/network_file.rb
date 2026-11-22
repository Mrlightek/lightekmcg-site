module LightekOffice
  class NetworkFile < ApplicationRecord
    self.table_name = 'lightek_network_office_files'
    belongs_to :channel, class_name: 'LightekTeam::NetworkChannel'
    belongs_to :editor_peer, class_name: 'LightekReservations::Peer'
    validates :kind, inclusion: {in: SharedFile::KINDS.keys}
    validates :title, presence: true, length: {maximum: 160}
    validates :content, presence: true
  end
end
