# frozen_string_literal: true
require "test_helper"
class Studio203CapabilitiesAccessTest < ActionDispatch::IntegrationTest
  test "unauthenticated request cannot access discovery" do
    get "/api/studio/capabilities", as: :json
    assert_not_equal 200, response.status
  end

  test "discovery source remains authorization independent and read only" do
    source = Studio::Capabilities::RailsReadAdapter.project_records(records: [], provider_outputs: {})
    assert_equal false, source.fetch('execution_authorized')
    assert_equal true, source.fetch('read_only')
    assert_equal [], source.fetch('records')
  end

  test "CanCanCan gate is available on the endpoint" do
    assert Api::Studio::CapabilitiesController < ApplicationController
    assert Api::Studio::CapabilitiesController.action_methods.include?('index')
    assert_respond_to Ability.new(User.new(role: 'client')), :can?
    assert_equal false, Ability.new(User.new(role: 'client')).can?(:read, NevaehCapability)
  end
end
