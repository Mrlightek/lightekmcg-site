require_relative 'broadcast_control_checks'
ActiveRecord::Schema.define do
  create_table(:lightek_commerce_products) { |t| t.string :name } unless table_exists?(:lightek_commerce_products)
  create_table(:hosting_packages) unless table_exists?(:hosting_packages)
end
require File.join(ROOT, 'db/migrate/20261114130000_add_agency_package_policies')
AddAgencyPackagePolicies.new.migrate(:up)
%w[installed_package package_usage package_storage].each { |file| require File.join(ROOT, "app/models/lightek_agency/#{file}") }
%w[package_policy package_features package_limits].each { |file| require File.join(ROOT, "app/services/lightek_agency/#{file}") }
require File.join(ROOT, 'app/controllers/concerns/lightek_agency_package_access')
ApplicationController.include LightekAgencyPackageAccess
LightekAgency::PackageLimits.install_callbacks!
class PackageStudioFixtureController < ApplicationController
  def index = render(json: {ok: true})
  def create = render(json: {created: true})
  def failing = render(json: {error: 'fixture'}, status: :unprocessable_entity)
  private
  def package_feature = 'studio'
end
class PackagePublicFixtureController < PackageStudioFixtureController
  allow_unauthenticated_access
end
class PackageAccountFixtureController < PackageStudioFixtureController
  private
  def package_feature = nil
end
Rails.application.routes.append do
  get '/package/studio', to: 'package_studio_fixture#index'
  post '/package/studio', to: 'package_studio_fixture#create'
  post '/package/failing', to: 'package_studio_fixture#failing'
  get '/package/public', to: 'package_public_fixture#index'
  get '/package/account', to: 'package_account_fixture#index'
end
Rails.application.reload_routes!
class AgencyPackageAccessChecks < BroadcastControlTest
  def self.runnable_methods = public_instance_methods.grep(/^test_package_/).map(&:to_s)
  def setup
    super
    @alice.update!(role: 'admin')
    @client = session_for
    install({})
  end
  def install(policy)
    LightekAgency::PackagePolicy.install!(user: @alice, configuration: {'source_key' => 'source-order-fixture', 'policy' => policy})
    @package = LightekAgency::InstalledPackage.find_by!(user: @alice)
  end
  def test_package_disabled_features_block_admin_direct_requests_and_public_api
    install('features' => {'studio' => {'enabled' => false}})
    @client.get '/package/studio', headers: headers
    assert_equal 403, @client.response.status
    @client.post '/package/studio', headers: headers
    assert_equal 403, @client.response.status
    @client.get '/package/public', headers: {'Accept' => 'application/json'}
    assert_equal 403, @client.response.status
    @client.get '/package/account', headers: headers
    assert_equal 200, @client.response.status
    assert LightekAgency::PackagePolicy.allowed?(@alice, 'commerce')
    assert_raises(LightekAgency::PackagePolicy::Denied) { LightekPwa::Policy.new(user: @alice, site: @site).authorize!('studio') }
    assert_nil LightekAgency::PackageFeatures.for_controller('identity_security')
    assert_nil LightekAgency::PackageFeatures.for_controller('installations')
  end
  def test_package_successful_writes_are_metered_and_failures_release_the_reservation
    install('features' => {'studio' => {'monthly_writes' => 1}})
    @client.post '/package/failing', headers: headers
    assert_equal 422, @client.response.status
    assert_equal 0, @package.usages.sum(:used)
    @client.post '/package/studio', headers: headers
    assert_equal 200, @client.response.status
    assert_equal 1, @package.usages.sum(:used)
    @client.post '/package/studio', headers: headers
    assert_equal 403, @client.response.status
    @client.get '/package/studio', headers: headers
    assert_equal 200, @client.response.status
    ids = LightekAgency::PackagePolicy.reserve_write!(user: @alice, feature: 'studio', now: 1.month.from_now)
    assert_equal 1, ids.size
  end
  def test_package_user_and_site_quotas_cover_model_writes
    install('limits' => {'max_users' => User.count, 'max_sites' => DymondSite::Site.count})
    assert_raises(LightekAgency::PackagePolicy::Denied) { User.create!(role: 'member') }
    assert_raises(LightekAgency::PackagePolicy::Denied) { DymondSite::Site.create!(name: 'Extra', host: 'extra.test') }
    current = @package.policy.deep_dup
    current['limits']['max_users'] += 1
    @package.update!(policy: current)
    user = User.create!(role: 'member')
    assert user.persisted?
    assert_raises(LightekAgency::PackagePolicy::Denied) { User.create!(role: 'member') }
  end
  def test_package_storage_covers_blobs_before_upload_and_charges_shared_media_once
    install('limits' => {'max_storage_bytes' => 5})
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('abc'), filename: 'small.txt', content_type: 'text/plain', identify: false)
    assert_equal 3, @package.storage.sum(:bytes)
    before = ActiveStorage::Blob.count
    assert_raises(LightekAgency::PackagePolicy::Denied) do
      ActiveStorage::Blob.create_before_direct_upload!(filename: 'large.txt', byte_size: 3, checksum: 'fixture', content_type: 'text/plain')
    end
    assert_equal before, ActiveStorage::Blob.count
    scene = StudioProject.create!(owner: @alice, site: @site, name: 'Shared media').studio_scenes.first!
    scene.editor_source.attach(blob)
    scene.reload.blender_source.attach(blob)
    assert_equal 1, @package.storage.count
    assert_equal 3, @package.storage.sum(:bytes)
    # Existing, previously unmetered attachments count when a new policy starts.
    @package.storage.delete_all
    assert_raises(LightekAgency::PackagePolicy::Denied) do
      ActiveStorage::Blob.create_before_direct_upload!(filename: 'another.txt', byte_size: 3, checksum: 'fixture', content_type: 'text/plain')
    end
  end
  def test_package_installation_is_idempotent_and_rejects_another_source_order
    install('features' => {'mail' => {'enabled' => false}})
    assert_equal 1, LightekAgency::InstalledPackage.count
    assert @package.runtime?
    assert_raises(LightekAgency::PackagePolicy::Denied) do
      LightekAgency::PackagePolicy.install!(user: @alice, configuration: {'source_key' => 'other-order', 'policy' => {}})
    end
    assert_equal 'source-order-fixture', @package.reload.source_key
    assert_equal false, @package.policy.dig('features', 'mail', 'enabled')
  end
  def test_package_superadmin_override_does_not_grant_an_admin_a_role
    install('features' => {'studio' => {'enabled' => false}})
    @alice.update!(role: 'super_admin')
    @client.get '/package/studio', headers: headers
    assert_equal 200, @client.response.status
    @alice.update!(role: 'admin')
    @client.get '/package/studio', headers: headers
    assert_equal 403, @client.response.status
  end
  def test_package_capabilities_and_embedded_engines_map_to_feature_families
    expected = {'studio.scene.save' => 'studio', 'messaging.send' => 'messaging', 'community.post.create' => 'community', 'susu.contribution.checkout' => 'susu'}
    expected.each { |slug, feature| assert_equal feature, LightekAgency::PackageFeatures.for_controller('api/nevaeh', capability: slug) }
    assert_equal 'studio', LightekAgency::PackageFeatures.for_controller('dymond_studio/studio')
    assert_equal 'commerce', LightekAgency::PackageFeatures.for_controller('dymond_catalog/products')
    assert_equal 'payments', LightekAgency::PackageFeatures.for_controller('dymond_bank/accounts')
    assert_equal 'ott', LightekAgency::PackageFeatures.for_controller('dashboard/media_studio', action: 'save_application')
  end
end
