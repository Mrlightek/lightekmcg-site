# frozen_string_literal: true

module LightekCommunications
  class VoiceCarrierOperation < ApplicationRecord
    self.table_name = "lightek_voice_carrier_operations"

    belongs_to :service, class_name: "LightekCommunications::Service"
    belongs_to :operator, class_name: "User"
  end
end
