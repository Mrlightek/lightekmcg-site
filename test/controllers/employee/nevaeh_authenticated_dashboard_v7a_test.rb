# frozen_string_literal: true
require 'test_helper'

class NevaehAuthenticatedDashboardV7aTest < ActionDispatch::IntegrationTest
  PASSWORD = 'nevaeh-dashboard-http-test'

  setup { Current.reset if Current.respond_to?(:reset) }
  teardown { Current.reset if Current.respond_to?(:reset) }

  def sign_in_as(role)
    user = User.create!(email_address: "nevaeh-ui-#{SecureRandom.hex(8)}@example.test",
      first_name: 'Nevaeh', last_name: 'Console', role: role, password: PASSWORD)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    assert_response :redirect
    assert Session.where(user_id: user.id).exists?
    user
  end

  test 'unauthenticated users cannot read the capability HTML or service JSON' do
    get employee_nevaeh_capabilities_path
    refute response.successful?
    get employee_nevaeh_services_path(format: :json)
    refute response.successful?
  end

  test 'employee receives HTML capabilities inside authenticated application' do
    sign_in_as('employee')
    get employee_nevaeh_capabilities_path
    assert_response :success
    assert_includes response.media_type, 'text/html'
    assert_includes response.body, 'Nevaeh Capabilities'
    assert_includes response.body, 'Read-only'
  end

  test 'admin accesses shared JSON API without enabling execution' do
    sign_in_as('admin')
    get employee_nevaeh_capabilities_path(format: :json)
    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload.fetch('read_only')
    assert_kind_of Array, payload.fetch('capabilities')
    get employee_nevaeh_services_path(format: :json)
    assert_response :success
    services = JSON.parse(response.body)
    assert_equal true, services.fetch('read_only')
  end

  test 'capability endpoints do not expose mutation verbs' do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path('/employee/nevaeh/capabilities', method: :post)
    end
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path('/employee/nevaeh/services', method: :delete)
    end
    assert_equal 'studio.asset.ingest', Rails.application.routes.recognize_path(
      '/employee/nevaeh/capabilities/studio.asset.ingest', method: :get).fetch(:key)
  end

  test 'nav initializer declares one native feature with only implemented routes' do
    source = File.read(Rails.root.join('config/initializers/nevaeh_nav.rb'))
    assert_equal 1, source.scan('DymondDash::FeatureRegistry.register do').length
    assert_includes source, 'feature.slug = :nevaeh'
    %w[employee_nevaeh_capabilities_path employee_nevaeh_services_path employee_tickets_path].each do |helper|
      assert_includes source, helper
      assert Rails.application.routes.url_helpers.respond_to?(helper)
    end
  end
end
