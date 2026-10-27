require "test_helper"
require "minitest/mock"

class LightekBusinessPayoutsTest < ActionDispatch::IntegrationTest
  def user
    User.create!(first_name: "Business", last_name: "Seller",
      role: "client", email_address: "seller-#{SecureRandom.hex(8)}@example.test",
      password: "business-payout-test-2026!")
  end

  def login!(actor)
    post "/session", params: {email_address: actor.email_address, password: "business-payout-test-2026!"}
    assert_response :redirect
  end

  test "payout settings require customer login" do
    get "/dashboard/business/payments/payouts"
    assert_response :redirect
  end

  test "business payout setup remains inside Lightek UI" do
    actor = user
    login!(actor)
    get "/dashboard/business/payments/payouts"
    assert_response :success
    assert_select "h1", text: "Business payouts"
    assert_select "#lightek-connect-onboarding" if ENV["STRIPE_PUBLISHABLE_KEY"].present?
  end

  test "connected user obtains short lived embedded account session" do
    actor = user
    actor.update!(stripe_connect_account_id: "acct_test12345")
    login!(actor)
    LightekBusiness::ConnectSession.stub(:create!, "accs_test_fixture_secret") do
      post "/dashboard/business/payments/payouts/session", as: :json
      assert_response :success
      assert_equal "accs_test_fixture_secret", response.parsed_body.fetch("client_secret")
    end
  end

  test "Stripe configuration problems fail without inventing payout readiness" do
    actor = user
    actor.update!(stripe_connect_account_id: "acct_test12345")
    login!(actor)
    LightekBusiness::ConnectSession.stub(:create!, ->(*) { raise LightekBusiness::ConnectSession::Unavailable, "unavailable" }) do
      post "/dashboard/business/payments/payouts/session", as: :json
      assert_response :service_unavailable
      refute response.parsed_body.key?("client_secret")
    end
  end
end
