# Exercise the real transport boundary, including Vault credential selection and
# SSH stdin. These doubles never connect to a server or read production secrets.
require_relative "fleet_updates_test" unless defined?(FleetUpdatesTest)
require Rails.root.join("app/services/gatekeeper/website_owner_access").to_s
require Rails.root.join("app/services/gatekeeper/website_deployment").to_s
begin
  require "net/ssh"
rescue LoadError
  module Net
    module SSH
      def self.start(*) = raise("Unexpected real SSH access in isolated tests")
    end
  end
  $LOADED_FEATURES << "net/ssh.rb"
end
unless defined?(LightekVault::Service)
  module LightekVault
    class Service
      def self.checkout!(**) = raise("Unexpected real Vault access in isolated tests")
    end
  end
end

class FleetUpdatesTest
  class TransportChannel
    attr_reader :input
    def initialize
      @input = +""
    end
    def exec(_command)
      yield self, true
    end
    def send_data(text) = @input << text
    def eof!; end
    def on_data(&callback) = @data = callback
    def on_extended_data(&callback); end
    def on_request(_name, &callback) = @exit = callback
    def finish
      @data.call(self, JSON.generate({"status" => "succeeded"}))
      @exit.call(self, Struct.new(:read_long).new(0))
    end
  end

  class TransportConnection
    attr_reader :channel
    def initialize = @channel = TransportChannel.new
    def open_channel = yield(channel)
    def loop = channel.finish
  end

  def transport_round_trip(node:, payload:, registry: false, &checkout)
    connection = TransportConnection.new
    ssh = ->(_host, _user, **options, &block) do
      assert_equal "root", _user
      block.call(connection)
    end
    LightekVault::Service.stub(:checkout!, checkout) do
      Net::SSH.stub(:start, ssh) do
        Gatekeeper::Fleet::Transport.run!(node: node, domain: "customer.example.com", requested_by: "operator",
          operation_id: 123, payload: payload, script_name: registry ? "update_installation.py" : "update_native_installation.py", registry: registry)
      end
    end
    JSON.parse(connection.channel.input)
  end

  def test_vault_root_credential_does_not_replace_deployment_payload
    node = installation.gatekeeper_node
    node.update!(metadata: {"node_credential_secret_slug" => "test-node-root"})
    config = {domain: "customer.example.com", source_sha: "a" * 40, deployment: {app_root: "/var/www/customer"}}
    received = transport_round_trip(node: node, payload: config) do |**args|
      assert_equal "test-node-root", args[:slug]
      assert_equal "node_bootstrap", args[:purpose]
      {"root_password" => +"test-root-password-never-send-in-job"}
    end
    assert_equal "customer.example.com", received["domain"]
    assert_equal "a" * 40, received["source_sha"]
    assert_equal "/var/www/customer", received.dig("deployment", "app_root")
    refute_includes received.to_json, "root_password"
    refute_includes received.to_json, "test-root-password"
  end

  def test_installation_and_registry_credentials_preserve_original_job_fields
    node = installation.gatekeeper_node
    node.update!(metadata: {"website_deployments" => {"customer.example.com" => {"credential_slug" => "test-site"}}})
    original = ENV["LIGHTEK_FLEET_REGISTRY_SECRET_SLUG"]
    ENV["LIGHTEK_FLEET_REGISTRY_SECRET_SLUG"] = "test-registry"
    config = {domain: "customer.example.com", source_sha: "b" * 40, adapter: "docker_compose"}
    received = transport_round_trip(node: node, payload: config, registry: true) do |**args|
      args[:slug] == "test-site" ? {"ssh_password" => +"test-ssh-password", "owner_password" => +"test-owner-password"} :
        {"username" => +"registry-reader", "password" => +"test-registry-password"}
    end
    assert_equal "b" * 40, received["source_sha"]
    assert_equal "docker_compose", received["adapter"]
    assert_equal "registry-reader", received.dig("registry", "username")
    refute_includes received.to_json, "ssh_password"
    refute_includes received.to_json, "owner_password"
  ensure
    ENV["LIGHTEK_FLEET_REGISTRY_SECRET_SLUG"] = original
  end
end
