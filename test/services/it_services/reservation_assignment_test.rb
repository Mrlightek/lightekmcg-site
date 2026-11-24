require "test_helper"

class ItServicesReservationAssignmentTest < ActiveSupport::TestCase
  test "customer cannot attach a reservation owned by someone else" do
    customer = User.new(id: 101)
    other = User.new(id: 202)
    request = ItServiceRequest.new(user: customer)
    reservation = LightekReservations::Reservation.new(customer: other)
    assert_raises(ArgumentError) do
      ItServices::ReservationAssignment.call!(request: request, reservation: reservation, actor: customer)
    end
  end

  test "another actor cannot attach a customer's reservation" do
    customer = User.new(id: 101)
    other = User.new(id: 202)
    request = ItServiceRequest.new(user: customer)
    reservation = LightekReservations::Reservation.new(customer: customer)
    assert_raises(ArgumentError) do
      ItServices::ReservationAssignment.call!(request: request, reservation: reservation, actor: other)
    end
  end
end
