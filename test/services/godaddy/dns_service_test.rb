require "test_helper"

class GodaddyDnsServiceTest < ActiveSupport::TestCase
  setup do
    @previous_domains = ENV["GODADDY_DOMAINS"]
    @previous_token = ENV["GODADDY_PAT"]
    ENV["GODADDY_DOMAINS"] = "lightekmcg.com"
    ENV["GODADDY_PAT"] = "legacy-token"
  end

  teardown do
    ENV["GODADDY_DOMAINS"] = @previous_domains
    ENV["GODADDY_PAT"] = @previous_token
  end

  test "uses legacy token only when vault has no configured secret" do
    LightekVault::Secret.stub(:exists?, false) do
      assert_equal "legacy-token", Godaddy::DnsService.new(zone: "lightekmcg.com").send(:token)
    end
  end

  test "prefers vault token and its scoped checkout" do
    LightekVault::Secret.stub(:exists?, true) do
      LightekVault::Service.stub(:checkout!, ->(**opts) {
        assert_equal "godaddy-dns", opts.fetch(:slug)
        assert_equal "Godaddy::DnsService", opts.fetch(:consumer)
        assert_equal "dns_management", opts.fetch(:purpose)
        {"token" => "vault-token"}
      }) do
        assert_equal "vault-token", Godaddy::DnsService.new(zone: "lightekmcg.com").send(:token)
      end
    end
  end

  test "vault access denial never silently falls back" do
    LightekVault::Secret.stub(:exists?, true) do
      LightekVault::Service.stub(:checkout!, ->(**) { raise LightekVault::Service::AccessDenied, "denied" }) do
        assert_raises(Godaddy::DnsService::ConfigurationError) do
          Godaddy::DnsService.new(zone: "lightekmcg.com").send(:token)
        end
      end
    end
  end

  test "rejects domains outside configured allowlist" do
    assert_raises(Godaddy::DnsService::ConfigurationError) { Godaddy::DnsService.new(zone: "other.com") }
  end
end
