# frozen_string_literal: true
require 'test_helper'
require 'securerandom'
class NevaehGeneratorV7aTest < ActionDispatch::IntegrationTest
  PASSWORD = 'nevaeh-generator-http-test'
  def sign_in(role)
    user = User.create!(email_address: "nv-draft-#{SecureRandom.hex(8)}@example.test", first_name: 'Nevaeh', last_name: 'Operator', role: role, password: PASSWORD)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    assert_response :redirect
  end
  test 'anonymous generator routes denied' do
    get employee_nevaeh_generator_path
    refute response.successful?
    post employee_nevaeh_generator_create_path, params: { key: 'test.build' }
    refute response.successful?
  end
  test 'administrator views HTML and JSON inventory' do
    sign_in('super_admin')
    get employee_nevaeh_generator_path
    assert_response :success
    assert_select 'section[aria-label="Nevaeh draft generator"]'
    get employee_nevaeh_generator_path(format: :json)
    assert_response :success
    assert_equal false, JSON.parse(response.body).fetch('executable')
  end
  test 'admin rejects unknown capability without writing app source' do
    sign_in('super_admin')
    post employee_nevaeh_generator_create_path, params: { key: "missing.#{SecureRandom.hex(8)}" }
    assert_response :unprocessable_entity
  end
  test 'normal employee cannot access generation' do
    sign_in('employee')
    get employee_nevaeh_generator_path
    refute response.successful?
    post employee_nevaeh_generator_create_path, params: { key: 'missing.example' }
    refute response.successful?
  end
end
