require "test_helper"

class LightekSettings::WebsiteIdentityTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @operator = User.create!(email_address: "workspace-#{SecureRandom.hex(8)}@example.test",
      first_name: "Workspace", last_name: "Operator", role: "super_admin", password: SecureRandom.hex(24))
    @site = DymondSite::Site.create!(tenant: @operator, name: "Extra workspace",
      host: "workspace-#{SecureRandom.hex(8)}.example.test")
    @identity = LightekSettings::WebsiteIdentity
  end

  test "hiding a managed site removes it only from the overview and can be reversed" do
    @site.update!(manifest: { "network_ledger" => true })

    @identity.set_overview_hidden!(site: @site, hidden: true, request_host: "example.com")
    refute @identity.overview_sites_for(@operator).exists?(@site.id)
    assert @identity.sites_for(@operator).exists?(@site.id)
    assert @site.reload.manifest["network_ledger"]

    @identity.set_overview_hidden!(site: @site, hidden: false, request_host: "example.com")
    assert @identity.overview_sites_for(@operator).exists?(@site.id)
  end

  test "permanent deletion requires the exact hostname and removes only the selected website" do
    other = DymondSite::Site.create!(tenant: @operator, name: "Another workspace",
      host: "workspace-#{SecureRandom.hex(8)}.example.test")
    assert_raises(LightekSettings::WebsiteIdentity::RemovalDenied) do
      @identity.delete!(site: @site, confirmation: other.host, request_host: "example.com")
    end
    assert DymondSite::Site.exists?(@site.id)

    @identity.delete!(site: @site, confirmation: @site.host, request_host: "example.com")
    refute DymondSite::Site.exists?(@site.id)
    assert DymondSite::Site.exists?(other.id)
    assert User.exists?(@operator.id)
  end

  test "the current hostname cannot be hidden or deleted and managed sites cannot be deleted" do
    assert_raises(LightekSettings::WebsiteIdentity::RemovalDenied) do
      @identity.set_overview_hidden!(site: @site, hidden: true, request_host: @site.host)
    end
    assert_raises(LightekSettings::WebsiteIdentity::RemovalDenied) do
      @identity.delete!(site: @site, confirmation: @site.host, request_host: @site.host)
    end

    @site.update!(manifest: { "network_ledger" => true })
    assert_raises(LightekSettings::WebsiteIdentity::RemovalDenied) do
      @identity.delete!(site: @site, confirmation: @site.host, request_host: "example.com")
    end
    assert DymondSite::Site.exists?(@site.id)
    refute @identity.overview_hidden?(@site.reload)
  end

  test "a workspace configured for public demo requests cannot be deleted" do
    LightekAgency::DemoSetting.create!(agency: @operator, public_site: @site, public_enabled: true)

    error = assert_raises(LightekSettings::WebsiteIdentity::RemovalDenied) do
      @identity.delete!(site: @site, confirmation: @site.host, request_host: "example.com")
    end
    assert_match(/demo settings/, error.message)
    assert DymondSite::Site.exists?(@site.id)
  end
end
