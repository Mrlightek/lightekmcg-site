module ItServices
  class CoverageClaim < ApplicationRecord
    self.table_name = "it_service_coverage_claims"

    belongs_to :period, class_name: "ItServices::CoveragePeriod"
    belongs_to :reservation, class_name: "LightekReservations::Reservation"

    attr_readonly :reservation_id, :service_request_id
  end
end
