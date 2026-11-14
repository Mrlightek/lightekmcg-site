require_relative 'reservation_federation_checks'
require ROOT.join('app/models/lightek_agency/installed_package').to_s
require ROOT.join('app/controllers/dashboard/reseller_packages_controller').to_s
Dashboard::ResellerPackagesController.layout false
class AgencyResellerHttpChecks < ReservationFederationChecks
  def self.runnable_methods = public_instance_methods.grep(/^test_package_editor/).map(&:to_s)
  def test_package_editor_renders_real_form_and_saves_owned_profile
    @guest.update!(role: 'white_label')
    @peer.site.update!(tenant: @guest)
    # The central editor uses the same catalog service as the remote offer API.
    get '/dashboard/reseller-packages', headers: {'X-Test-User' => @guest.id.to_s}
    assert_response :success
    assert_select 'input[name="offer[package_policy][features][studio][enabled]"][type="checkbox"]', count: 1
    assert_select 'input[name="offer[package_policy][limits][max_users]"]', count: 1
    post '/dashboard/reseller-packages', params: {offer: {source_id: @package.id, name: 'Basic client',
      price_cents: 15000, published: '1', package_policy: {features: {studio: {enabled: '0'}}}}}, headers: {'X-Test-User' => @guest.id.to_s}
    assert_response :redirect
    resource = LightekReservations::Resource.find_by!(site: @peer.site, name: 'Basic client')
    assert_equal false, resource.product.package_policy.dig('features', 'studio', 'enabled')
    get '/dashboard/reseller-packages', params: {offer_id: resource.id}, headers: {'X-Test-User' => @guest.id.to_s}
    assert_response :success
    assert_select 'input[name="offer[id]"][value=?]', resource.id.to_s
    assert_select 'input[name="offer[package_policy][features][studio][enabled]"][checked]', count: 0
  end
  def test_package_editor_refuses_another_agency_website
    @guest.update!(role: 'white_label')
    assert_raises(ActiveRecord::RecordNotFound) do
      get '/dashboard/reseller-packages', params: {site_id: @site.id}, headers: {'X-Test-User' => @guest.id.to_s}
    end
  end
end
