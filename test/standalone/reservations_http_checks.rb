require_relative 'reservations_checks'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'
require 'tmpdir'
class ReservationHarness < Rails::Application
  config.root = Dir.mktmpdir('reservation-http-')
  config.eager_load = false
  config.secret_key_base = 'test-reservations-only-' * 5
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.autoload_paths = []
end
ReservationHarness.initialize!
class ApplicationController < ActionController::Base
  helper_method :current_user
  before_action :authenticate
  def resume_session = current_user
  def current_user = User.find_by(id: request.headers['X-Test-User'])
  def authenticate = (head(:unauthorized) unless current_user)
  def self.allow_unauthenticated_access(only:) = skip_before_action(:authenticate, only: only)
  def self.skip_authorization_check = nil
end
module Dashboard
  class SettingsHomeController < ApplicationController
    before_action { head :forbidden unless current_user&.role.in?(%w[admin super_admin]) }
  end
end
module DymondDash
  ApplicationController = ::ApplicationController
end
module LightekCommerce
  class StripeCheckout
    class Unavailable < StandardError; end
    def self.start!(**) = OpenStruct.new(url: 'https://checkout.stripe.com/test-session')
  end
end
module Api; end
require ROOT.join('app/controllers/api/reservation_federation_controller').to_s
require ROOT.join('app/controllers/network_reservations_controller').to_s
require ROOT.join('app/controllers/reservations_controller').to_s
require ROOT.join('app/controllers/dashboard/reservations_controller').to_s
require ROOT.join('app/controllers/dashboard/commerce_payouts_controller').to_s
ReservationHarness.routes.draw do
  eval(ROOT.join('config/routes/reservations.rb').read, binding)
  get '/my/installations', to: 'reservations#index', as: :installations
  get '/my/installations/:id', to: 'reservations#show', as: :installation
  get '/dashboard/commerce/orders', to: 'reservations#index', as: :dashboard_commerce_orders
  get '/dashboard/commerce/payouts', to: 'dashboard/commerce_payouts#index', as: :dashboard_commerce_payouts
  get '/dashboard/susu/payout-account', to: 'reservations#index', as: :dashboard_susu_payout_account
end
ApplicationController.prepend_view_path ROOT.join('app/views')
# The isolated harness renders the real templates without the private engine layout.
Dashboard::ReservationsController.layout 'reservations'
module HarnessAssetHelpers
  def stylesheet_link_tag(*) = ''.html_safe
  def javascript_include_tag(*) = ''.html_safe
end
ApplicationController.helper HarnessAssetHelpers
class ReservationsHttpChecks < ActionDispatch::IntegrationTest
  include ReservationHarness.routes.url_helpers
  def app = ReservationHarness
  def setup
    # Use the same production-model fixtures as the data checks.
    @fixtures = ReservationsChecks.new('unused')
    @fixtures.setup
    @owner, @guest, @other, @site, @resource, @start = %i[owner guest other site resource start].map { |key| @fixtures.instance_variable_get("@#{key}") }
    host! 'example.test'
  end
  def as(user) = {'X-Test-User' => user.id.to_s}
  def test_public_catalog_renders_on_white_label_host
    get '/reservations'
    assert_response :success
    assert_includes response.body, 'Creative consultation'
    assert_includes response.body, 'My reservations'
  end
  def test_unauthenticated_person_cannot_book
    post '/my/reservations', params: {resource_id: @resource.id, starts_at: @start.iso8601, checkout_key: SecureRandom.uuid}
    assert_response :unauthorized
    assert_equal 0, LightekReservations::Reservation.count
  end
  def test_customer_books_and_manages_free_appointment
    post '/my/reservations', params: {resource_id: @resource.id, starts_at: @start.iso8601, checkout_key: SecureRandom.uuid}, headers: as(@guest)
    assert_response :redirect
    follow_redirect!(headers: as(@guest))
    assert_response :success
    assert_includes response.body, 'Confirmed'
    assert_includes response.body, 'Reschedule appointment'
  end
  def test_other_customer_cannot_read_reservation
    booking = @fixtures.reserve
    assert_raises(ActiveRecord::RecordNotFound) { get "/my/reservations/#{booking.id}", headers: as(@other) }
  end
  def test_calendar_is_downloadable_without_join_link_leak
    booking = @fixtures.reserve
    get "/my/reservations/#{booking.id}/calendar", headers: as(@guest)
    assert_response :success
    assert_includes response.body, 'BEGIN:VCALENDAR'
    assert_match(/text\/calendar/, response.content_type)
    refute_includes response.body, 'join_url'
  end
  def test_guest_catalog_cannot_select_someone_elses_site
    assert_raises(ActiveRecord::RecordNotFound) { get '/reservations', params: {site_id: @fixtures.instance_variable_get(:@foreign_site).id} }
  end
  def test_client_cannot_open_operator_dashboard
    get '/dashboard/reservations', headers: as(@guest)
    assert_response :forbidden
  end
  def test_dashboard_renders_real_calendar_and_form
    get '/dashboard/reservations', params: {site_id: @site.id}, headers: as(@owner)
    assert_response :success
    assert_includes response.body, 'Front desk'
    assert_includes response.body, 'Server resort packages'
    assert_includes response.body, 'Time off & maintenance'
  end
  def test_white_label_admin_cannot_edit_other_site
    assert_raises(ActiveRecord::RecordNotFound) { get '/dashboard/reservations', params: {site_id: @site.id}, headers: as(@other) }
  end
  def test_operator_form_creates_opening_hours_without_raw_json
    post '/dashboard/reservations/experiences', params: {site_id: @site.id, resource: {name: 'Hair appointment', kind: 'service',
      timezone: 'America/New_York', duration_minutes: 30, capacity: 1, buffer_minutes: 10, notice_minutes: 60,
      cancellation_hours: 24, published: '1', cost_floor_cents: 0, accommodations_text: "Consultation\nFinish",
      opening_hours: {'1'=>{'open'=>'09:00','close'=>'17:00'}}, compute: {}}}, headers: as(@owner)
    assert_response :redirect
    resource = LightekReservations::Resource.find_by!(name: 'Hair appointment')
    assert_equal({'1'=>[['09:00','17:00']]}, resource.hours)
    assert_equal ['Consultation','Finish'], resource.accommodations
  end
  def test_customer_cannot_choose_cheaper_amount_in_request
    @resource.update!(product: @fixtures.product)
    post '/my/reservations', params: {resource_id: @resource.id, starts_at: @start.iso8601, checkout_key: SecureRandom.uuid, amount_cents: 1}, headers: as(@guest)
    assert_response :redirect
    booking = LightekReservations::Reservation.last
    assert_equal 5000, booking.order.total_cents
    assert_equal 'held', booking.status
  end
  def test_payout_form_saves_weekly_preference
    patch '/dashboard/commerce/payout-schedule', params: {site_id: @site.id, cadence: 'weekly', enabled: '1'}, headers: as(@owner)
    assert_response :redirect
    assert_equal 'weekly', LightekCommerce::PayoutSchedule.find_by!(merchant: @owner).cadence
  end
  def test_public_availability_omits_guest_names
    @fixtures.reserve
    get '/reservations/slots', params: {resource_id: @resource.id, date: @start.to_date.iso8601}
    assert_response :success
    assert_equal 'America/New_York', response.parsed_body['timezone']
    refute_includes response.body, @guest.email_address
  end
  def test_booking_mutations_require_csrf_tokens_for_cookie_sessions
    ReservationsController.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post '/my/reservations', params: {resource_id: @resource.id, starts_at: @start.iso8601, checkout_key: SecureRandom.uuid}, headers: as(@guest)
    end
    assert_equal 0, LightekReservations::Reservation.count
  ensure
    ReservationsController.allow_forgery_protection = false
  end
  def test_private_session_link_is_hidden_until_payment_confirmation
    @resource.update!(product: @fixtures.product, join_url: 'https://private.example.test/session-secret')
    booking = @fixtures.reserve
    get '/reservations'
    refute_includes response.body, 'session-secret'
    get "/my/reservations/#{booking.id}", headers: as(@guest)
    refute_includes response.body, 'session-secret'
    booking.order.update!(status: 'paid', paid_at: Time.current)
    get "/my/reservations/#{booking.id}", headers: as(@guest)
    assert_includes response.body, 'session-secret'
  end

end
