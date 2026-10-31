# frozen_string_literal: true

require "test_helper"

class GatekeeperWebsiteDnsConflictTest < ActiveSupport::TestCase
  def stub_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **kwargs| implementation.call(*args, **kwargs) }
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  test "matching A record does not conceal another stale A record" do
    dns = Object.new
    dns.define_singleton_method(:records) do
      [
        { "id" => "new", "name" => "client-1", "type" => "A", "data" => "8.8.8.8" },
        { "id" => "old", "name" => "client-1", "type" => "A", "data" => "9.9.9.9" }
      ]
    end
    dns.define_singleton_method(:create_record!) { |_| flunk "unexpected create" }
    dns.define_singleton_method(:update_record!) { |_, _| flunk "unexpected update" }
    stub_method(Godaddy::DnsService, :zones, -> { ["lightekmcg.com"] }) do
      stub_method(Godaddy::DnsService, :new, ->(**) { dns }) do
        assert_raises(Gatekeeper::WebsiteDnsPublication::Conflict) do
          Gatekeeper::WebsiteDnsPublication.call!(hostname: "client-1.lightekmcg.com", ipv4: "8.8.8.8")
        end
      end
    end
  end
end
