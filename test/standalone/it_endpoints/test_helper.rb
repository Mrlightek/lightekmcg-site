# frozen_string_literal: true

# Runs the real endpoint controllers, services and migrations in an isolated
# Rails application. Account sign-in uses fixture credentials.
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = ENV.fetch("LIGHTEK_ENDPOINT_TEST_DATABASE_URL")
require "minitest/autorun"
require "active_record/railtie"
require "action_controller/railtie"
require "action_dispatch/testing/integration"
require "tmpdir"

ENDPOINT_REPO = Pathname.new(File.expand_path("../../..", __dir__))
module LightekPwa
  module SourceRuntime
    def self.writable!(record:) = true
  end
end

class EndpointAcceptanceApp < Rails::Application
  config.load_defaults 8.0
  config.root = Dir.mktmpdir("it-endpoints")
  config.eager_load = false
  config.active_record.maintain_test_schema = false
  config.secret_key_base = "endpoint-fixture-credentials-only" * 4
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.cache_store = :memory_store
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
end

EndpointAcceptanceApp.initialize!
require "rails/test_help"

raise "Use an empty PostgreSQL test database" if ActiveRecord::Base.connection_pool.with_connection { |db| db.tables.any? }

ActiveRecord::Schema.define do
  create_table :users do |table|
    table.string :email_address, null: false
    table.string :password_digest, null: false
    table.string :first_name
    table.string :last_name
    table.string :role
    table.datetime :access_suspended_at
  end
end

%w[
  20261030160000_create_network_managed_devices:CreateNetworkManagedDevices
  20261030170000_add_enrollment_to_network_managed_devices:AddEnrollmentToNetworkManagedDevices
  20261123235000_create_it_service_requests:CreateItServiceRequests
  20261124001000_add_it_service_device_ownership:AddItServiceDeviceOwnership
  20261124093000_add_health_telemetry_to_network_managed_devices:AddHealthTelemetryToNetworkManagedDevices
  20261124110000_create_it_managed_device_incidents:CreateItManagedDeviceIncidents
  20261124133000_add_managed_monitoring_consent_to_network_managed_devices:AddManagedMonitoringConsentToNetworkManagedDevices
  20261124160000_create_it_device_maintenance_actions:CreateItDeviceMaintenanceActions
  20261124161000_schedule_it_device_maintenance_actions:ScheduleItDeviceMaintenanceActions
  20261124162000_gate_it_device_backup_recovery:GateItDeviceBackupRecovery
  20261124163000_add_patch_target_to_it_device_maintenance_actions:AddPatchTargetToItDeviceMaintenanceActions
].each do |entry|
  path, migration = entry.split(":")
  require ENDPOINT_REPO.join("db/migrate", path)
  Object.const_get(migration).new.migrate(:up)
end

require ENDPOINT_REPO.join("app/models/application_record")
class User < ApplicationRecord
  has_secure_password
end

class Current < ActiveSupport::CurrentAttributes
  attribute :session
end

require ENDPOINT_REPO.join("app/controllers/concerns/authentication")
class ApplicationController < ActionController::Base
  include Authentication
  layout false
  prepend_view_path ENDPOINT_REPO.join("app/views")

  def resume_session
    Current.session ||= Struct.new(:user, :connect_delegation).new(User.find(session[:fixture_user])) if session[:fixture_user]
  end

  def current_user = Current.session&.user

  private

  def require_authentication
    head :unauthorized unless resume_session
  end
end

class EndpointFixtureSessionsController < ApplicationController
  allow_unauthenticated_access

  def create
    user = User.authenticate_by(email_address: params[:email_address], password: params[:password])
    return head :unauthorized unless user

    session[:fixture_user] = user.id
    redirect_to "/"
  end
end

module ItServices; end
%w[
  models/network_managed_device models/it_device_maintenance_action models/it_service_request
  services/lightek_people/lifecycle_access services/it_services/device_telemetry services/it_services/endpoint_maintenance
  models/it_managed_device_incident services/it_services/managed_device_posture services/it_services/managed_fleet_incidents
  services/it_services/incident_escalation
  controllers/it_service_requests_controller controllers/gatekeeper_controller
].each { |path| require ENDPOINT_REPO.join("app", path) }

EndpointAcceptanceApp.routes.draw do
  post "/gatekeeper/device", to: "gatekeeper#device_api", as: :gatekeeper_device
  post "/session", to: "endpoint_fixture_sessions#create", as: :session
  resources :it_service_requests, only: %i[index new] do
    post :managed_device_monitoring, on: :collection
    post :cancel_device_check, on: :collection
    post :consent_to_device_recovery, on: :collection
    post :consent_to_device_patch, on: :collection
  end
end

class ActionDispatch::IntegrationTest
  include EndpointAcceptanceApp.routes.url_helpers
end
