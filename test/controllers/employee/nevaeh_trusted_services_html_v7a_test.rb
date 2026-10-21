# frozen_string_literal: true
require 'test_helper'

class NevaehTrustedServicesHtmlV7aTest < ActionDispatch::IntegrationTest
  PASSWORD = 'nevaeh-services-presentation-test'

  def sign_in(role)
    user = User.create!(email_address: "nevaeh-services-#{SecureRandom.hex(8)}@example.test",
      first_name: 'Nevaeh', last_name: 'Viewer', role: role, password: PASSWORD)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    assert_response :redirect
  end

  test 'super admin sees native HTML page and explicit JSON remains available' do
    sign_in('super_admin')
    get employee_nevaeh_services_path
    assert_response :success
    assert_equal 'text/html', response.media_type
    assert_includes response.body, 'Nevaeh Trusted Services'
    assert_includes response.body, 'Registration and file presence do not grant execution permission'
    assert_select 'table[aria-label="Registered services"]'
    get employee_nevaeh_services_path(format: :json)
    assert_response :success
    assert_equal 'application/json', response.media_type
    data = JSON.parse(response.body)
    assert_equal true, data.fetch('read_only')
    assert_kind_of Array, data.fetch('services')
  end

  test 'anonymous visitors cannot view HTML or JSON' do
    get employee_nevaeh_services_path
    refute response.successful?
    get employee_nevaeh_services_path(format: :json)
    refute response.successful?
  end

  test 'trusted services retains GET only routes' do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path('/employee/nevaeh/services', method: :post)
    end
  end
end
