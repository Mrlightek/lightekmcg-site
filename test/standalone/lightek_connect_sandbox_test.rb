require_relative "lightek_connect_test"
ActiveRecord::Schema.define do
  create_table(:gatekeeper_nodes) do |t|
    t.string :name; t.string :ip_address; t.string :ssh_user; t.integer :ssh_port
    t.string :status; t.references :owner, polymorphic: true
  end
end
migration = Rails.root.join("db/migrate/20261112210000_create_lightek_connect_sandboxes.rb").read.sub("Migration[8.0]", "Migration[7.2]")
eval(migration, TOPLEVEL_BINDING)
CreateLightekConnectSandboxes.new.migrate(:up)
require Rails.root.join("app/models/gatekeeper_node")
require Rails.root.join("app/models/lightek_connect/sandbox")
require Rails.root.join("app/services/lightek_connect/sandboxes")
module Godaddy
  class DnsService
    def self.zones = ["lightekmcg.com"]
  end
end
module Gatekeeper
  module Fleet
    class Transport
      def self.run!(**) = {}
    end
  end
end
module LightekConnect
  class SandboxJob
    def self.perform_later(*) = true
  end
end
class LightekConnectSandboxTest < Minitest::Test
  def setup
    @operator = User.create!(role: "super_admin")
    @node = GatekeeperNode.create!(name: "test-#{SecureRandom.hex(4)}", owner: @operator, ip_address: "203.0.113.10", ssh_user: "root", ssh_port: 22, status: "healthy")
    key = SecureRandom.hex(12)
    @sandbox = LightekConnect::Sandbox.create!(user: @operator, gatekeeper_node: @node, key: key, domain: "wp-test-#{key}.lightekmcg.com", credential_slug: "test-#{key}", status: "ready", metadata: {"zone" => "lightekmcg.com", "ip_address" => @node.ip_address, "dns_id" => "owned", "dns_type" => "A"})
  end
  def teardown
    LightekConnect::Sandbox.delete_all
    GatekeeperNode.delete_all
  end
  def test_agencies_cannot_allocate_or_delete_operator_test_environments
    agency = User.create!(role: "white_label")
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Sandboxes.create!(actor: agency, node_id: @node.id) }
    assert_raises(Gatekeeper::Hosting::Access::Denied) { LightekConnect::Sandboxes.delete!(actor: agency, sandbox: @sandbox, confirmation: @sandbox.domain) }
  end
  def test_cleanup_requires_exact_hostname
    assert_raises(ArgumentError) { LightekConnect::Sandboxes.delete!(actor: @operator, sandbox: @sandbox, confirmation: "lightekmcg.com") }
    assert_equal "ready", @sandbox.reload.status
  end
  def test_only_unchanged_owned_dns_record_is_deleted
    record = {"id" => "owned", "name" => @sandbox.domain.delete_suffix(".lightekmcg.com"), "type" => "A", "data" => @node.ip_address}
    dns = Minitest::Mock.new
    dns.expect(:records, [record])
    dns.expect(:delete_record!, true, ["owned"])
    Godaddy::DnsService.stub(:new, dns) { LightekConnect::Sandboxes.remove_dns!(@sandbox) }
    dns.verify
  end
  def test_dns_changes_stop_cleanup
    record = {"id" => "owned", "name" => "different", "type" => "A", "data" => @node.ip_address}
    dns = Minitest::Mock.new
    dns.expect(:records, [record])
    Godaddy::DnsService.stub(:new, dns) do
      assert_raises(ArgumentError) { LightekConnect::Sandboxes.remove_dns!(@sandbox) }
    end
    dns.verify
  end
  def test_running_installation_cannot_be_deleted_early
    @sandbox.update!(status: "installing")
    assert_raises(ArgumentError) { LightekConnect::Sandboxes.delete!(actor: @operator, sandbox: @sandbox, confirmation: @sandbox.domain) }
  end
  def test_worker_marks_ready_only_after_matching_remote_receipt
    @sandbox.update!(status: "queued")
    secret = {"admin_password" => "test".dup}
    receipt = {"key" => @sandbox.key, "domain" => @sandbox.domain, "status" => "ready"}
    LightekConnect::Sandboxes.stub(:prepare_dns!, true) do
      LightekVault::Service.stub(:checkout!, secret) do
        Gatekeeper::Fleet::Transport.stub(:run!, receipt) { LightekConnect::Sandboxes.perform!(@sandbox, "install") }
      end
    end
    assert_equal "ready", @sandbox.reload.status
    assert_equal "", secret.fetch("admin_password")
    assert_equal receipt, @sandbox.metadata["receipt"]
  end
  def test_wrong_receipt_never_marks_installation_ready
    @sandbox.update!(status: "queued")
    LightekConnect::Sandboxes.stub(:prepare_dns!, true) do
      LightekVault::Service.stub(:checkout!, {}) do
        Gatekeeper::Fleet::Transport.stub(:run!, {"key" => "wrong", "status" => "ready"}) { LightekConnect::Sandboxes.perform!(@sandbox, "install") }
      end
    end
    assert_equal "failed", @sandbox.reload.status
  end
  def test_successful_cleanup_disables_credential_and_marks_deleted
    @sandbox.update!(status: "deleting")
    receipt = {"key" => @sandbox.key, "domain" => @sandbox.domain, "status" => "deleted"}
    disabled = []
    LightekConnect::Sandboxes.stub(:remove_dns!, true) do
      LightekVault::Service.stub(:disable!, ->(**args) { disabled << args.fetch(:slug) }) do
        Gatekeeper::Fleet::Transport.stub(:run!, receipt) { LightekConnect::Sandboxes.perform!(@sandbox, "delete") }
      end
    end
    assert_equal "deleted", @sandbox.reload.status
    assert_equal [@sandbox.credential_slug], disabled
  end
  def test_credentials_expose_only_wordpress_login_and_clear_checkout_copy
    secret = {"admin_username" => "lightek_test".dup, "admin_password" => "generated-password".dup, "database_password" => "db-secret".dup}
    LightekVault::Service.stub(:checkout!, secret) do
      credentials = LightekConnect::Sandboxes.credentials!(actor: @operator, sandbox: @sandbox)
      assert_equal %w[admin_password admin_username], credentials.keys.sort
      assert_equal "generated-password", credentials["admin_password"]
    end
    assert secret.values.all?(&:empty?)
  end

end
