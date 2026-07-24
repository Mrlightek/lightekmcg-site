# frozen_string_literal: true
# Registers the Booking domain service with the kernel.
Rails.application.config.to_prepare do
  Lightek::ServiceRegistry.register(:booking, DymondBooking::BookingService)
end
