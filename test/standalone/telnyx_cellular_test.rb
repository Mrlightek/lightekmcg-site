# frozen_string_literal: true

require "action_controller"
require "active_record"
require "active_job"
require "active_support/all"
require "lockbox"
require "minitest/autorun"
require "minitest/mock"
require "securerandom"

ENV["TELNYX_SIM_CARD_GROUP_ID"] = "d7df8cfe-1a2b-4984-915c-41aec285f615"
ENV["TELNYX_SIM_IPV4_CIDR"] = "10.50.0.0/16"
test_url = ENV["CELLULAR_TEST_DATABASE_URL"]
ActiveRecord::Base.establish_connection(test_url || { adapter: "sqlite3", database: ":memory:" })
if test_url
  schema = "cellular_fixture_#{SecureRandom.hex(5)}"
  ActiveRecord::Base.connection.execute("CREATE SCHEMA #{schema}")
  ActiveRecord::Base.connection.schema_search_path = schema
end
ActiveRecord::Base.connection.create_table(:users)
ActiveRecord::Migration.verbose = false
require_relative "../../db/migrate/20261123163000_create_user_esims"
CreateUserEsims.new.migrate(:up)
Lockbox.master_key = Lockbox.generate_key

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
class User < ApplicationRecord; end

require_relative "../../app/models/user_esim"
require_relative "../../app/models/telnyx_esim_event"
require_relative "../../app/controllers/webhooks/telnyx_controller"
%w[wireless_client cellular_hub webhook_signature provision_esim_service manage_sim_service].each do |service|
  require_relative "../../app/services/telnyx/#{service}"
end
require_relative "../../app/jobs/application_job"
%w[provision_esim_job provision_vps_route_job sync_esim_status_job].each do |job|
  require_relative "../../app/jobs/#{job}"
end
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil)

Minitest.after_run { ActiveRecord::Base.connection.execute("DROP SCHEMA #{schema} CASCADE") } if schema

class TelnyxCellularTest < Minitest::Test
  SIM = "ea1582ec-bbd7-4a22-861b-5badbff25b70"
  ICCID = "89310410106543789301"
  CODE = 'LPA:1$example.test$fixture-code'

  def setup
    TelnyxEsimEvent.delete_all
    UserEsim.delete_all
    User.delete_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    @user = User.create!
    @group = ENV.fetch("TELNYX_SIM_CARD_GROUP_ID")
    @request = SecureRandom.uuid
    @card = { "id" => SIM, "iccid" => ICCID, "sim_card_group_id" => @group, "status" => { "value" => "disabled" } }
  end

  def order
    Telnyx::ProvisionEsimService.call(user: @user, sim_card_group_id: @group,
      plan_limit_mb: 1_024, customer_wg_peer_ip: "172.25.10.2", request_key: @request)
  end

  def test_allocation_is_unique_and_skips_linux_reserved_table_ids
    esim = order.reload
    assert_equal esim.id + (esim.id < 154 ? 99 : 102), esim.routing_table_id
    assert_equal 100, UserEsim.create!(esim.attributes.except("id", "routing_table_id", "request_key").merge(
      id: 1, request_key: SecureRandom.uuid)).reload.routing_table_id unless esim.id == 1
    last_before_reserved = esim.dup
    last_before_reserved.update!(id: 153, request_key: SecureRandom.uuid)
    first_after_reserved = esim.dup
    first_after_reserved.update!(id: 154, request_key: SecureRandom.uuid)
    assert_equal [252, 256], [last_before_reserved.reload.routing_table_id, first_after_reserved.reload.routing_table_id]
  end

  def test_same_checkout_is_idempotent_and_cannot_be_claimed_by_another_user
    esim = order
    assert_equal esim.id, order.id
    @user = User.create!
    assert_raises(Telnyx::ProvisionEsimService::Invalid) { order }
  end

  def test_real_api_contract_and_job_install_the_confirmed_route
    esim = order
    tag = "lightek-esim-#{@request}"
    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.post("/v2/actions/purchase/esims") do |env|
      assert_equal({ "amount" => 1, "sim_card_group_id" => @group, "status" => "disabled", "tags" => [tag] }, JSON.parse(env.body))
      [202, {}, JSON.generate(data: [@card])]
    end
    stubs.get("/v2/sim_cards/#{SIM}") { [200, {}, JSON.generate(data: @card)] }
    stubs.patch("/v2/sim_cards/#{SIM}") do |env|
      limit = { "amount" => "1024", "unit" => "MB" }
      assert_equal({ "data_limit" => limit }, JSON.parse(env.body))
      [200, {}, JSON.generate(data: @card.merge("data_limit" => limit))]
    end
    stubs.get("/v2/sim_cards/#{SIM}/activation_code") { [200, {}, JSON.generate(data: { activation_code: CODE })] }
    stubs.post("/v2/sim_cards/#{SIM}/actions/enable") { [202, {}, JSON.generate(data: { status: "in-progress" })] }
    client = test_client(stubs)
    hub = Minitest::Mock.new
    hub.expect(:check_peer!, nil, ["172.25.10.2"])
    hub.expect(:install!, nil, ["10.50.1.40", "172.25.10.2", esim.reload.routing_table_id])
    Telnyx::ProvisionEsimService.new(esim, client: client, hub: hub).provision!

    esim.reload
    assert_equal "awaiting_device", esim.status
    assert_equal SIM, esim.telnyx_sim_id
    refute_includes esim[:lpa_activation_code], CODE
    assert_equal CODE, esim.lpa_activation_code
    assert Base64.strict_decode64(esim.activation_qr_base64).start_with?("\x89PNG".b)
    assert_nil esim.assigned_private_ip

    @card["ipv4"] = "10.50.1.40"
    @card["status"] = { "value" => "enabled" }
    Telnyx::WirelessClient.stub(:new, client) do
      Telnyx::CellularHub.stub(:new, hub) do
        ProvisionVpsRouteJob.perform_now(esim.id)
        ProvisionVpsRouteJob.perform_now(esim.id)
      end
    end
    assert_equal ["10.50.1.40", "enabled"], esim.reload.values_at(:assigned_private_ip, :status)
    assert esim.route_installed_at
    hub.verify
    stubs.verify_stubbed_calls
  end

  def test_purchase_timeout_reconciles_without_replaying_a_charge
    esim = order
    client = Minitest::Mock.new
    hub = Minitest::Mock.new
    hub.expect(:check_peer!, nil, ["172.25.10.2"])
    hub.expect(:check_peer!, nil, ["172.25.10.2"])
    def client.purchase(group_id:, tag:)
      raise Telnyx::WirelessClient::Retryable, "response lost"
    end
    client.expect(:find_purchase, [@card], group_id: @group, tag: "lightek-esim-#{@request}")
    client.expect(:sim, @card.merge("actions_in_progress" => true), [SIM])

    2.times do
      assert_raises(Telnyx::WirelessClient::Retryable) { Telnyx::ProvisionEsimService.new(esim, client: client, hub: hub).provision! }
    end
    assert_equal SIM, esim.reload.telnyx_sim_id
    client.verify
    hub.verify
  end

  def test_sync_uses_current_carrier_status_and_deduplicates_event
    esim = order
    esim.update!(telnyx_sim_id: SIM, route_installed_at: Time.current)
    client = Minitest::Mock.new
    client.expect(:sim, @card.merge("status" => { "value" => "data_limit_exceeded" }), [SIM])
    event = SecureRandom.uuid
    Telnyx::WirelessClient.stub(:new, client) do
      2.times { SyncEsimStatusJob.perform_now(esim.id, event) }
    end
    assert_equal "data_limit_exceeded", esim.reload.status
    assert_equal 1, TelnyxEsimEvent.count
    client.verify
  end

  def test_ed25519_requires_exact_bytes_and_rejects_replay
    key = Ed25519::SigningKey.generate
    ENV["TELNYX_PUBLIC_KEY"] = Base64.strict_encode64(key.verify_key.to_bytes)
    now = Time.now.to_i
    body = '{"data":{}}'
    signature = Base64.strict_encode64(key.sign("#{now}|#{body}"))
    verifier = Telnyx::WebhookSignature
    assert verifier.valid?(timestamp: now.to_s, signature: signature, body: body, now: now)
    refute verifier.valid?(timestamp: now.to_s, signature: signature, body: body + "\n", now: now)
    refute verifier.valid?(timestamp: now.to_s, signature: signature, body: body, now: now + 301)
  end

  def test_webhook_enqueues_only_after_signature_validation
    esim = order
    esim.update!(telnyx_sim_id: SIM)
    key = Ed25519::SigningKey.generate
    ENV["TELNYX_PUBLIC_KEY"] = Base64.strict_encode64(key.verify_key.to_bytes)
    timestamp = Time.now.to_i.to_s
    event_id = SecureRandom.uuid
    body = JSON.generate(data: { id: event_id, event_type: "sim_card.status_changed",
      payload: { sim_card_id: SIM } })
    signature = Base64.strict_encode64(key.sign("#{timestamp}|#{body}"))
    headers = { "CONTENT_TYPE" => "application/json", "HTTP_TELNYX_TIMESTAMP" => timestamp,
      "HTTP_TELNYX_SIGNATURE_ED25519" => signature }
    webhook = Rack::MockRequest.new(Webhooks::TelnyxController.action(:create))

    assert_equal 401, webhook.post("/webhooks/telnyx", headers.merge(input: body + " ")).status
    assert_equal 204, webhook.post("/webhooks/telnyx", headers.merge(input: body)).status
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
    assert_equal [esim.id, event_id], jobs.find { |job| job[:job] == SyncEsimStatusJob }.fetch(:args)
  end

  def test_top_up_is_absolute_and_repeatable
    esim = order
    esim.update!(telnyx_sim_id: SIM, limit_applied_at: Time.current)
    client = Minitest::Mock.new
    client.expect(:set_limit, {}, [SIM, 2_048])
    service = Telnyx::ManageSimService.new(esim, client: client)

    2.times { service.top_up!(to_mb: "2048") }
    assert_equal 2_048, esim.reload.plan_limit_mb
    assert_raises(Telnyx::ManageSimService::Invalid) { service.top_up!(to_mb: 1_024) }
    client.verify
  end

  def test_nonzero_ssh_exit_is_an_error_and_host_key_check_is_required
    %w[HUB_VPS_HOST HUB_VPS_USER HUB_VPS_SSH_KEY HUB_VPS_KNOWN_HOSTS_FILE].each { |name| ENV[name] = name }
    status = Struct.new(:read_long).new(7)
    channel = Object.new
    channel.define_singleton_method(:on_request) { |_, &block| block.call(self, status) }
    channel.define_singleton_method(:exec) do |command, &block|
      raise "Unexpected command" unless command == "sudo -n /usr/local/bin/add_user_route.sh 10.50.9.8 172.25.10.2 100"
      block.call(self, true)
    end
    session = Object.new
    session.define_singleton_method(:open_channel) { |&block| block.call(channel) }
    session.define_singleton_method(:loop) {}
    start = ->(_host, _user, options, &block) do
      assert_equal :always, options.fetch(:verify_host_key)
      block.call(session)
    end
    Net::SSH.stub(:start, start) do
      error = assert_raises(Telnyx::CellularHub::Error) { Telnyx::CellularHub.new.install!("10.50.9.8", "172.25.10.2", 100) }
      assert_match(/exit 7/, error.message)
    end
  end

  private

  def test_client(stubs)
    connection = Faraday.new do |http|
      http.request :json
      http.adapter :test, stubs
    end
    Telnyx::WirelessClient.new(connection: connection)
  end
end
