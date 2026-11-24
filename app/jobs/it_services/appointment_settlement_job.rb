module ItServices
  class AppointmentSettlementJob < ApplicationJob
    queue_as :default

    def perform(request_id)
      return unless Enrollment.operations_ready?

      request = ItServiceRequest.find_by(id: request_id)
      CompletedAppointmentSettlement.call(request) if request
    end
  end
end
