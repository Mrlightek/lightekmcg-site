gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "active_support/all"
require "pathname"
require "tmpdir"
require "stringio"
require "ostruct"
module Rails
  class << self
    attr_accessor :root
    def env = "test"
  end
end
module Gatekeeper
  module WebsiteOwnerAccess; end
end
class GatekeeperNode < Struct.new(:metadata, :id); end
class User
  def self.find(*) = OpenStruct.new(id: 7, role: "client", email_address: "client@example.com")
end
require_relative "../../app/services/gatekeeper/website_readiness"
require_relative "../../app/services/gatekeeper/website_deployment"
class WebsiteDeploymentDispatchTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir
    Rails.root = Pathname.new(@directory)
    FileUtils.mkdir_p(Rails.root.join("tmp/website_deploy"))
    @service = Gatekeeper::WebsiteDeployment.new(actor: nil, node: nil, domain: "client.example.com")
  end
  def teardown = FileUtils.remove_entry(@directory)
  def run_receipt(receipt, outside: false, owner_email: nil)
    path = Rails.root.join(outside ? "outside.json" : "tmp/website_deploy/result.json")
    path.write(JSON.generate(receipt))
    output = "WEBSITE_DEPLOYMENT_PASS=https://client.example.com\nReceipt: #{path}\n"
    popen = ->(*, &block) { block.call(StringIO.new, StringIO.new(output), OpenStruct.new(value: OpenStruct.new(success?: true))) }
    Open3.stub(:popen2e, popen) { @service.run_packager({"domain" => "client.example.com", "owner_email" => owner_email}) }
  end
  def good_receipt
    {"url" => "https://client.example.com", "public_https_verified" => true,
      "owner_login_verified" => true, "health" => {"full_application_dashboard_verified" => true}}
  end
  def test_remote_execution_is_dispatched_instead_of_silently_returning_nil
    called = false
    @service.stub(:execute_remote, ->(config) { called = config == {"domain" => "client.example.com"}; {verified: true} }) do
      assert_equal({verified: true}, @service.execute({"domain" => "client.example.com"}))
    end
    assert called
  end
  def test_installer_success_marker_alone_cannot_mark_a_site_ready
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) { run_receipt({"url" => "https://client.example.com"}) }
  end
  def test_validated_login_and_full_dashboard_receipt_is_required
    assert_equal good_receipt, run_receipt(good_receipt)
    bad = good_receipt.merge("health" => {})
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) { run_receipt(bad) }
  end
  def pending_receipt
    good_receipt.merge('release' => 'revision', 'health' => {'verification_schema' => 2, 'domain' => 'client.example.com',
      'release' => 'revision', 'owner_email' => 'client@example.com', 'owner_authentication_verified' => true,
      'owner_onboarding_required' => true, 'owner_mfa_state' => 'enrollment_required', 'dashboard_mfa_gate_verified' => true,
      'verified_dashboard_paths' => Gatekeeper::WebsiteReadiness::DASHBOARD_PATHS, 'full_application_dashboard_verified' => false})
  end
  def test_pending_mfa_requires_exact_owner_release_and_complete_gate_proof
    receipt = pending_receipt
    assert_equal receipt, run_receipt(receipt, owner_email: 'client@example.com')
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) { run_receipt(receipt) }
    assert Gatekeeper::WebsiteReadiness.verified?(receipt, domain: 'client.example.com', owner_email: 'client@example.com')
    refute Gatekeeper::WebsiteReadiness.verified?(receipt, domain: 'client.example.com', owner_email: 'other@example.com')
    refute Gatekeeper::WebsiteReadiness.verified?(receipt, domain: 'other.example.com', owner_email: 'client@example.com')
    %w[owner_authentication_verified dashboard_mfa_gate_verified owner_onboarding_required].each do |flag|
      bad = Marshal.load(Marshal.dump(receipt)); bad['health'][flag] = false
      refute Gatekeeper::WebsiteReadiness.verified?(bad, domain: 'client.example.com', owner_email: 'client@example.com')
    end
    %w[release owner_email verified_dashboard_paths verification_schema].each do |flag|
      bad = Marshal.load(Marshal.dump(receipt)); bad['health'].delete(flag)
      refute Gatekeeper::WebsiteReadiness.verified?(bad, domain: 'client.example.com', owner_email: 'client@example.com')
    end
    refute Gatekeeper::WebsiteReadiness.verified?(receipt.merge('release' => 'stale'), domain: 'client.example.com', owner_email: 'client@example.com')
  end
  def test_receipt_cannot_be_read_outside_the_deployment_receipt_directory
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) { run_receipt(good_receipt, outside: true) }
  end
  def test_hostname_lookup_is_exact_and_cannot_match_a_longer_hostname_prefix
    actor = OpenStruct.new(persisted?: true, role: "super_admin")
    node = GatekeeperNode.new({"website_deployments" => {"client.example.com.evil.test" => {"owner_id" => 7}}}, 1)
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) do
      Gatekeeper::WebsiteDeployment.preview(actor: actor, record: node, domain: "client.example.com")
    end
  end
end
