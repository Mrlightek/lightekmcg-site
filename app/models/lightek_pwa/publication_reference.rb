module LightekPwa
  class PublicationReference < ApplicationRecord
    self.table_name = 'lightek_pwa_publication_references'
    belongs_to :peer, class_name: 'LightekReservations::Peer'
    belongs_to :post, optional: true
  end
end
