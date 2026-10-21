# frozen_string_literal: true
require 'test_helper'
class NevaehOverviewV7aTest < ActionDispatch::IntegrationTest
  PASSWORD = 'nevaeh-overview-test-pass'
  def sign_in(role)
    user = User.create!(email_address: "nv-overview-#{SecureRandom.hex(8)}@example.test",
      first_name: 'Nevaeh', last_name: 'Operator', role: role, password: PASSWORD)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    assert_response :redirect
  end

  test 'overview route is GET only and returns denied response anonymously' do
    assert_equal 'employee/nevaeh_overview', Rails.application.routes.recognize_path('/employee/nevaeh', method: :get).fetch(:controller)
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path('/employee/nevaeh', method: :post) }
    get employee_nevaeh_overview_path
    refute response.successful?
    get employee_nevaeh_overview_path(format: :json)
    refute response.successful?
  end

  test 'super admin sees native overview and explicit JSON' do
    sign_in('super_admin')
    get employee_nevaeh_overview_path
    assert_response :success
    assert_equal 'text/html', response.media_type
    assert_select 'section[aria-label="Nevaeh operating system overview"]'
    assert_select 'a[href="/employee/nevaeh/capabilities"]'
    assert_select 'a[href="/employee/nevaeh/services"]'
    get employee_nevaeh_overview_path(format: :json)
    assert_response :success
    assert_equal 'application/json', response.media_type
    data = JSON.parse(response.body)
    assert_equal true, data.fetch('read_only')
    assert_kind_of Hash, data.fetch('summary')
    assert_kind_of Array, data.fetch('services')
  end

  test 'native navigation includes overview and existing entries' do
    source = File.read(Rails.root.join('config/initializers/nevaeh_nav.rb'))
    assert_includes source, 'main_app.employee_nevaeh_overview_path'
    assert_includes source, 'main_app.employee_nevaeh_capabilities_path'
    assert_includes source, 'main_app.employee_nevaeh_services_path'
  end
end
