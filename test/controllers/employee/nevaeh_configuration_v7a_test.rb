# frozen_string_literal: true
require 'test_helper'
require 'fileutils'
class NevaehConfigurationV7aTest < ActionDispatch::IntegrationTest
  PASSWORD = 'nevaeh-configuration-http-test'
  setup do
    @key = "nv.test#{SecureRandom.hex(6)}"
  end
  teardown do
    path = Rails.root.join('config', 'nevaeh', 'capabilities', "#{@key}.yml")
    File.delete(path) if File.file?(path) && !File.symlink?(path)
    Current.reset if Current.respond_to?(:reset)
  end
  def sign_in(role)
    user = User.create!(email_address: "nv-config-#{SecureRandom.hex(8)}@example.test",
      first_name: 'Nevaeh', last_name: 'Operator', role: role, password: PASSWORD)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    assert_response :redirect
  end
  test 'anonymous access is rejected' do
    get employee_nevaeh_configuration_path
    refute response.successful?
    post employee_nevaeh_configuration_create_path, params: { key: @key }
    refute response.successful?
  end
  test 'employee is denied configuration mutations' do
    sign_in('employee')
    post employee_nevaeh_configuration_create_path, params: { key: @key }
    refute response.redirect? && response.redirect_url == employee_nevaeh_configuration_url
    refute File.exist?(Rails.root.join('config/nevaeh/capabilities', "#{@key}.yml"))
  end
  test 'super admin creates disabled draft and registers dependent job' do
    sign_in('super_admin')
    get employee_nevaeh_configuration_path
    assert_response :success
    assert_select 'section[aria-label="Nevaeh capability configuration"]'
    post employee_nevaeh_configuration_create_path, params: { key: @key }
    assert_response :redirect
    yaml = NevaehIntelligences::YamlCapabilityRegistryV7a.read(root: Rails.root.to_s, key: @key)
    assert_equal false, yaml.dig('capability', 'enabled')
    post employee_nevaeh_configuration_job_path(key: @key), params: { job_id: 'validate', service: 'studio.asset.validate' }
    assert_response :redirect
    post employee_nevaeh_configuration_job_path(key: @key), params: { job_id: 'process', service: 'studio.asset.process', after: 'validate' }
    assert_response :redirect
    yaml = NevaehIntelligences::YamlCapabilityRegistryV7a.read(root: Rails.root.to_s, key: @key)
    assert_equal %w[validate process], yaml.dig('capability', 'jobs').map { |j| j.fetch('id') }
    assert_equal ['validate'], yaml.dig('capability', 'jobs').last.fetch('depends_on')
    assert_equal false, yaml.dig('capability', 'enabled')
  end
  test 'invalid service identifier cannot be persisted' do
    sign_in('super_admin')
    post employee_nevaeh_configuration_create_path, params: { key: @key }
    post employee_nevaeh_configuration_job_path(key: @key), params: { job_id: 'unsafe', service: 'Kernel.system' }
    assert_response :redirect
    yaml = NevaehIntelligences::YamlCapabilityRegistryV7a.read(root: Rails.root.to_s, key: @key)
    assert_empty yaml.dig('capability', 'jobs')
  end
  test 'CLI and web share one registry and JSON includes draft' do
    sign_in('admin')
    post employee_nevaeh_configuration_create_path, params: { key: @key }
    get employee_nevaeh_configuration_path(format: :json)
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal false, data.fetch('executable')
    assert_includes data.fetch('capabilities').map { |c| c.fetch('key') }, @key
    assert_equal @key, NevaehIntelligences::YamlCapabilityRegistryV7a.list(root: Rails.root.to_s).find { |x| x['key'] == @key }.fetch('key')
  end
end
