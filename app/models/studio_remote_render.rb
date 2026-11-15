class StudioRemoteRender < ApplicationRecord
  belongs_to :peer, class_name: "LightekReservations::Peer"
  belongs_to :studio_operation
end
