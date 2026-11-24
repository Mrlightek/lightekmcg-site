module ItServices
  module SettlesCompletedAppointments
    extend ActiveSupport::Concern

    included do
      after_update_commit :enqueue_it_appointment_settlement, if: :saved_change_to_status?
    end

    private

    def enqueue_it_appointment_settlement
      ItServices::AppointmentSettlementJob.perform_later(id) if status == "resolved" && reservation_id
    rescue RedisClient::Error => error
      Rails.logger.error("IT appointment settlement enqueue failed request_id=#{id}: #{error.class}")
    end
  end
end
