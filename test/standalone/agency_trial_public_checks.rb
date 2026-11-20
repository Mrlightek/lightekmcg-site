require_relative 'agency_demo_checks'

require ROOT.join('db/migrate/20261120190000_create_lightek_agency_trials')
require ROOT.join('db/migrate/20261120200000_create_lightek_agency_trial_requests')
CreateLightekAgencyTrials.new.migrate(:up)
CreateLightekAgencyTrialRequests.new.migrate(:up)
require ROOT.join('app/models/lightek_agency/trial')
require ROOT.join('app/models/lightek_agency/trial_request')
LightekAgency::TrialRequest.generated_token_verifier = User.generated_token_verifier
ActiveRecord::Schema.define do
  add_column :users, :access_suspended_at, :datetime
  add_column :lightek_commerce_products, :slug, :string
  add_column :lightek_commerce_products, :currency, :string, default: 'usd'
  add_column :lightek_commerce_products, :track_inventory, :boolean, default: false
  add_column :lightek_commerce_products, :inventory_quantity, :integer, default: 0
end
LightekCommerce::Product.reset_column_information
User.reset_column_information
class User
  def access_active? = access_suspended_at.nil?
end
require ROOT.join('app/controllers/agency_trial_requests_controller')
AgencyTrialRequestsController.layout false
require ROOT.join('app/controllers/dashboard/agency_trials_controller')
Dashboard::AgencyTrialsController.layout false

class AgencyTrialPublicChecks < AgencyDemoChecks
  def self.runnable_methods = public_instance_methods.grep(/^test_public_agency_trial_/).map(&:to_s)

  def setup
    LightekAgency::TrialRequest.delete_all
    LightekAgency::Trial.delete_all
    super
    @platform = User.create!(role: 'super_admin', email_address: 'platform@example.test')
    @site = DymondSite::Site.create!(tenant: @platform, name: 'Lightek', host: 'agency.example.test',
      manifest: {LightekAgency::Trial::PUBLIC_SITE_FLAG => true})
    host! @site.host
    @contact = {first_name: 'Nia', last_name: 'Jones', email_address: 'NIA@example.test '}
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def teardown
    LightekAgency::TrialRequest.delete_all
    LightekAgency::Trial.delete_all
    super
  end

  def request_trial(contact = @contact)
    post request_agency_demo_path, params: {trial_request: contact}
    assert_redirected_to request_agency_demo_path
    assert_equal 303, response.status
    LightekAgency::TrialRequest.order(:id).last
  end

  def test_public_agency_trial_requires_no_agency_name_and_creates_only_after_confirmation
    get request_agency_demo_path
    assert_response :success
    assert_select 'form input[name="trial_request[email_address]"]'
    assert_select 'form input[name="trial_request[brand_name]"]', count: 0
    assert_includes response.body, '$200'
    trial_request = request_trial
    assert_equal 'nia@example.test', trial_request.email_address
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size
    assert_equal 0, LightekAgency::Trial.count
    refute User.exists?(email_address: trial_request.email_address)
    request_trial
    assert_equal 1, LightekAgency::TrialRequest.count
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size

    mail = LightekAgency::DemoRequestMailer.agency_trial_confirmation(trial_request.id)
    assert_equal ['nia@example.test'], mail.to
    link = URI.parse(mail.text_part.decoded.lines.find { |line| line.start_with?('https://') }.strip)
    assert_equal @site.host, link.host
    assert_match %r{\A/request-agency-demo/confirm/}, link.path
    path = link.path
    get path
    assert_response :success
    assert_equal 0, LightekAgency::Trial.count

    post path
    trial = LightekAgency::Trial.sole
    assert_response :redirect
    assert_match %r{/account/setup/}, response.location
    assert_equal 'client', trial.prospect.role
    assert_equal 'My agency', trial.brand_name
    assert_equal @site.id, trial.billing_site_id
    assert_in_delta 3.days.to_i, trial.expires_at - Time.current, 5
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size
    assert trial_request.reload.confirmed_at?
    post path
    assert_redirected_to request_agency_demo_path
    assert_equal 1, LightekAgency::Trial.count
  end

  def test_public_agency_trial_publish_control_opens_and_closes_the_public_form
    @site.update!(manifest: {'retained_setting' => 'untouched'})
    assert_raises(ActiveRecord::RecordNotFound) { get request_agency_demo_path }
    login(@platform)
    patch publish_dashboard_agency_trials_path, params: {site_id: @site.id, enabled: '1'}
    assert_redirected_to dashboard_agency_trials_path
    assert LightekAgency::Trial.public_site?(@site.reload)
    assert_equal 'untouched', @site.manifest.fetch('retained_setting')
    get dashboard_agency_trials_path
    assert_select 'a[href=?]', "https://#{@site.host}/request-agency-demo"
    get request_agency_demo_path
    assert_response :success

    patch publish_dashboard_agency_trials_path, params: {site_id: @site.id, enabled: '0'}
    assert_redirected_to dashboard_agency_trials_path
    assert_raises(ActiveRecord::RecordNotFound) { get request_agency_demo_path }
  end

  def test_public_agency_trial_price_is_set_from_dashboard_and_shown_on_request_form
    login(@platform)
    patch pricing_dashboard_agency_trials_path, params: {site_id: @site.id, annual_price: '275.25'}
    assert_redirected_to dashboard_agency_trials_path
    assert_equal 27_525, LightekAgency::Trial.annual_price_cents(@site)
    get dashboard_agency_trials_path
    assert_select 'input[name="annual_price"][value="275.25"]'
    get request_agency_demo_path
    assert_includes response.body, '$275.25'
  end

  def test_public_agency_trial_is_bound_to_the_published_website
    path = confirm_agency_demo_path(request_trial.generate_token_for(:confirmation))
    other = DymondSite::Site.create!(tenant: @platform, name: 'Other platform site', host: 'other.example.test', manifest: @site.manifest)
    host! other.host
    assert_raises(ActiveRecord::RecordNotFound) { post path }

    host! @site.host
    @site.update!(manifest: {})
    assert_raises(ActiveRecord::RecordNotFound) { post path }
    assert_equal 0, LightekAgency::Trial.count

    @site.update!(tenant: @employer, manifest: {LightekAgency::Trial::PUBLIC_SITE_FLAG => true})
    assert_raises(ActiveRecord::RecordNotFound) { get request_agency_demo_path }
  end

  def test_public_agency_trial_reuses_an_eligible_login_without_reassigning_it
    existing = User.create!(role: 'client', email_address: 'nia@example.test')
    trial_request = request_trial
    post confirm_agency_demo_path(trial_request.generate_token_for(:confirmation))
    trial = LightekAgency::Trial.sole
    assert_redirected_to dashboard_agency_trial_path(trial)
    assert_equal existing.id, trial.prospect_id
    assert_equal 'client', existing.reload.role
    assert_nil existing.agency_id
    refute existing.password_setup_required?
  end

  def test_public_agency_trial_never_replaces_an_existing_login_or_elevates_it
    @other.update!(agency: @employer)
    trial_request = request_trial(@contact.merge(email_address: @other.email_address))
    role = @other.role
    post confirm_agency_demo_path(trial_request.generate_token_for(:confirmation))
    assert_redirected_to new_session_path
    assert_equal role, @other.reload.role
    assert_equal @employer.id, @other.agency_id
    assert_equal 0, LightekAgency::Trial.count
  end
end
