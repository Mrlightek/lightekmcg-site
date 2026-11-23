# frozen_string_literal: true

module LightekCommunications
  class VoiceAddOn < ApplicationRecord
    self.table_name = "lightek_voice_add_ons"

    belongs_to :peer, class_name: "LightekReservations::Peer"
    belongs_to :order, class_name: "LightekCommerce::Order"
  end
end
