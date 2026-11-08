require_relative 'reservations_http_checks'
raise 'PostgreSQL is required for reservation concurrency checks' unless ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
class ReservationsConcurrencyChecks < Minitest::Test
  def test_two_guests_cannot_claim_the_same_last_place
    fixtures = ReservationsChecks.new('unused'); fixtures.setup
    resource = fixtures.instance_variable_get(:@resource)
    guests = [fixtures.instance_variable_get(:@guest), fixtures.instance_variable_get(:@other)]
    starts_at = fixtures.instance_variable_get(:@start)
    ready, go, results = Queue.new, Queue.new, Queue.new
    threads = guests.map do |guest|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true; go.pop
          begin
            reservation = LightekReservations::Booking.reserve!(customer: User.find(guest.id),
              resource: LightekReservations::Resource.find(resource.id), starts_at: starts_at.iso8601,
              checkout_key: SecureRandom.uuid)
            results << [:booked, reservation.id]
          rescue LightekReservations::Availability::Invalid
            results << [:unavailable]
          rescue StandardError => error
            results << [:error, error.class.name, error.message]
          end
        end
      end
    end
    2.times { ready.pop }; 2.times { go << true }; threads.each(&:join)
    outcomes = 2.times.map { results.pop }
    assert_equal 1, outcomes.count { |row| row.first == :booked }, outcomes.inspect
    assert_equal 1, outcomes.count { |row| row.first == :unavailable }, outcomes.inspect
    assert_equal 1, resource.reservations.occupying.count
  end
end
