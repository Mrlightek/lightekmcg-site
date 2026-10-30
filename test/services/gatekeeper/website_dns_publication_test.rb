# frozen_string_literal: true

require "test_helper"

class GatekeeperWebsiteDnsPublicationTest < ActiveSupport::TestCase
  def stub_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **kwargs| implementation.call(*args, **kwargs) }
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  test "rejects private addresses before any DNS request" do
    assert_raises(ArgumentError) do
      Gatekeeper::WebsiteDnsPublication.call!(hostname: "client-1.lightekmcg.com", ipv4: "127.0.0.1")
    end
  end

  test "refuses to publish to an unmanaged DNS zone" do
    stub_method(Godaddy::DnsService, :zones, -> { [] }) do
      assert_raises(Gatekeeper::WebsiteDnsPublication::NotConfigured) do
        Gatekeeper::WebsiteDnsPublication.call!(hostname: "client-1.lightekmcg.com", ipv4: "8.8.8.8")
      end
    end
  end

  test "does not duplicate an existing matching A record" do
    fake = Object.new
    fake.define_singleton_method(:records) { [{ "id" => "r1", "name" => "client-1", "type" => "A", "data" => "8.8.8.8" }] }
    fake.define_singleton_method(:create_record!) { |_| flunk "duplicate DNS record" }
    fake.define_singleton_method(:update_record!) { |_, _| flunk "unnecessary DNS update" }
    stub_method(Godaddy::DnsService, :zones, -> { ["lightekmcg.com"] }) do
      stub_method(Godaddy::DnsService, :new, ->(**) { fake }) do
        stub_method(Resolv, :getaddresses, ->(*) { ["8.8.8.8"] }) do
          result = Gatekeeper::WebsiteDnsPublication.call!(hostname: "client-1.lightekmcg.com", ipv4: "8.8.8.8")
          assert_equal true, result.fetch("verified")
        end
      end
    end
  end
end
