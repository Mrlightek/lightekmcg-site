require "test_helper"
require_relative "../support/studio_live_test_support"
class LiveBroadcastsTest < ActionDispatch::IntegrationTest
  def actor(role = "admin")
    User.create!(first_name: "Live", last_name: "Operator", role: role, email_address: "http-live-#{SecureRandom.hex(6)}@example.test", password: "Live-test-password-2026!")
  end
  def login(user)
    post "/session", params: {email_address: user.email_address, password: "Live-test-password-2026!"}
    assert_response :redirect
  end
  test "only administrators can open the capture workspace" do
    get "/dashboard/live"
    assert_response :redirect
    login(actor("client")); get "/dashboard/live"; assert_response :forbidden
  end
  test "workspace exposes preview test and disabled unconfigured TikTok" do
    login(actor)
    with_live_stub(Studio::Live::Encoder, :available?, true) do
      with_live_stub(Studio::Live::Destination, :configured?, false) { get "/dashboard/live" }
    end
    assert_response :success
    assert_select "[data-live-studio] video[data-preview][muted]"
    assert_select "[data-destination] option[value='tiktok'][disabled]"
    assert_select "[data-share]", text: "Choose screen"
    assert_select "[data-camera]", text: "Enable camera"
    assert_select "[data-layout] option[value='camera']", text: "Camera only"
    assert_select "[data-layout] option[value='combined']", text: "Screen + camera"
    assert_select "input[name='stream_key']", count: 0
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end
  test "private recording download enforces owner and complete state" do
    user = actor
    operation = with_live_stub(Studio::Live::Encoder, :available?, true) { Studio::Live::Sessions.create!(user: user, title: "Download test", destination: "test") }
    login(actor)
    get "/dashboard/live/#{operation.id}/recording"
    assert_response :forbidden
    login(user)
    get "/dashboard/live/#{operation.id}/recording"
    assert_response :not_found
  end
  test "session creation returns a ticket and no credentials" do
    user = actor; login(user)
    with_live_stub(Studio::Live::Encoder, :available?, true) { post "/dashboard/live/sessions", params: {title: "Capture", destination: "test"}, as: :json }
    assert_response :created
    assert response.parsed_body["ticket"].present?
    refute response.parsed_body.key?("stream_key")
    refute response.parsed_body.key?("server_url")
  end
end
