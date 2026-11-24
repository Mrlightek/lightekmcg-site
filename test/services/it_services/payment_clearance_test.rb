require "test_helper"

class ItServicesPaymentClearanceTest < ActiveSupport::TestCase
  test "rejects missing appointment instead of inventing payment" do
    assert_raises(ArgumentError) do
      ItServices::PaymentClearance.verify!(request: ItServiceRequest.new)
    end
  end

  test "confirmed appointment without an order cannot dispatch" do
    customer = Struct.new(:email_address).new("customer@example.test")
    resource = Struct.new(:kind).new("service")
    reservation = Struct.new(:id, :customer_id, :resource, :status, :order)
      .new(17, 9, resource, "confirmed", nil)
    request = Struct.new(:reservation, :user_id, :user).new(reservation, 9, customer)
    assert_raises(ArgumentError) { ItServices::PaymentClearance.verify!(request: request) }
  end

  test "unpaid order blocks dispatch" do
    customer = Struct.new(:email_address).new("customer@example.test")
    resource = Struct.new(:kind).new("service")
    order = Struct.new(:id, :customer_email).new(22, customer.email_address)
    reservation = Struct.new(:id, :customer_id, :resource, :status, :order, :paid?)
      .new(17, 9, resource, "confirmed", order, false)
    request = Struct.new(:reservation, :user_id, :user).new(reservation, 9, customer)
    assert_raises(ArgumentError) { ItServices::PaymentClearance.verify!(request: request) }
  end
end
