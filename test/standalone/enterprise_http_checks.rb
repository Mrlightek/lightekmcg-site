require_relative 'enterprise_accounting_checks'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'
require 'tmpdir'
class EnterpriseHarness < Rails::Application
  config.root = Dir.mktmpdir('enterprise-http-')
  config.eager_load = false
  config.secret_key_base = 'enterprise-test-only-' * 8
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.cache_store = :memory_store
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.autoload_paths = []
end
EnterpriseHarness.initialize!
class Current < ActiveSupport::CurrentAttributes
  attribute :session
end
require ROOT.join('app/models/session')
class User
  has_many :sessions
  def authenticate(password) = password == 'fixture-password' ? self : false
  def self.authenticate_by(values)
    user=find_by(email_address: values[:email_address]);user if user&.authenticate(values[:password])
  end
  def can_access_feature?(*) = true
end
require ROOT.join('app/controllers/concerns/authentication')
class ApplicationController < ActionController::Base
  before_action { Current.reset }
  include Authentication
  helper_method :current_user
  def current_user = Current.session&.user
  def main_app = self
  def self.skip_authorization_check = nil
  def self.rate_limit(**) = nil unless respond_to?(:rate_limit)
end
module Dashboard
  class SettingsHomeController < ApplicationController
    before_action :require_settings_operator!
    def require_settings_operator! = head(:forbidden)
  end
end
class IdentityProtectedController < ApplicationController
  def index = render(plain: "signed in #{current_user.id}")
end
require ROOT.join('app/helpers/accounting_workspace_helper')
require ROOT.join('app/controllers/concerns/lightek_identity/sensitive_session')
%w[sessions identity_security identity_challenges identity_sso dashboard/accounting dashboard/directory dashboard/compliance dashboard/people].each { |f| require ROOT.join("app/controllers/#{f}_controller") }
require ROOT.join('app/models/lightek_compliance/monitor')
require ROOT.join('app/services/lightek_compliance/access')
require ROOT.join('app/services/lightek_compliance/sources')
%w[accounting_import accounting_refresh jurisdiction_monitor].each { |f| require ROOT.join("app/jobs/#{f}_job") }
[IdentitySecurityController,IdentityChallengesController,Dashboard::AccountingController,Dashboard::DirectoryController,Dashboard::ComplianceController,Dashboard::PeopleController].each { |klass| klass.layout false }
EnterpriseHarness.routes.draw do
  get '/connect/management', to: 'connect_management#show'
  post '/connect/management', to: 'connect_management#create'
  post '/api/reservations/federation/connect/redeem', to: 'api/connect_federation#redeem'
  post '/api/reservations/federation/connect/validate', to: 'api/connect_federation#validate_session'
  resources :dashboard_agencies, path: '/dashboard/agencies', controller: 'dashboard/agencies', only: %i[index create update] do
    member do
      post :create_client
      post :send_setup_invitation
      patch :update_terms
    end
  end
  get '/my/installations/:id', to: 'installations#show', as: :installation
  get '/my/installations', to: 'installations#index', as: :installations
  get '/dashboard/home', to: 'dashboard/client_home#index', as: :dashboard_client_home
  get '/dashboard/settings', to: 'dashboard/account_settings#index', as: :dashboard_settings_home
  get '/dashboard/business', to: 'dashboard/business_hub#index', as: :dashboard_business_hub
  get '/my/reservations', to: 'identity_protected#index', as: :my_reservations
  resources :passwords, param: :token
  resource :session,only: %i[new create destroy]
  eval(ROOT.join('config/routes/enterprise_identity.rb').read,binding)
  eval(ROOT.join('config/routes/accounting.rb').read,binding)
  get '/after-login',to: 'identity_protected#index'
  get '/after-login/servers',to: 'identity_protected#index',as: :dashboard_servers
  get '/after-login/employee',to: 'identity_protected#index',as: :dashboard_nevaeh_os
  eval(ROOT.join('config/routes/people.rb').read,binding)
  get '/dashboard/servers/:id',to: 'identity_protected#index',as: :dashboard_server
end
ApplicationController.prepend_view_path ROOT.join('app/views')
ApplicationController.helper(Module.new { def stylesheet_link_tag(*) = ''.html_safe })
class EnterpriseHttpChecks < ActionDispatch::IntegrationTest
  include EnterpriseHarness.routes.url_helpers
  def app = EnterpriseHarness
  def setup
    Rails.cache.clear
    @fixture=EnterpriseAccountingChecks.new('unused');@fixture.setup
    %i[employer other worker manager book account income].each { |key| instance_variable_set("@#{key}",@fixture.instance_variable_get("@#{key}")) }
    host! 'example.test'
  end
  def login(user)
    seed=LightekIdentity::Mfa.begin!(user)
    now=Time.current
    LightekIdentity::Mfa.verify!(user,LightekIdentity::Mfa.code(seed,now.to_i/30),enrolling: true,now: now)
    post session_path,params: {email_address: user.email_address,password: 'fixture-password'}
    assert_redirected_to identity_challenge_path
    assert_equal 0,user.sessions.count
    post identity_challenge_path,params: {otp: LightekIdentity::Mfa.code(seed,Time.current.to_i/30 + 1)}
    assert_response :redirect
    assert_equal 1,user.sessions.count
    assert LightekIdentity::Mfa.fresh?(user.sessions.last)
  end
  def workspace(tab = 'ledger',**params) = dashboard_accounting_path({employer_id: @employer.id,book_id: @book.id,tab: tab}.merge(params))
  def test_password_does_not_create_a_full_session_before_mfa_and_replay_fails
    login(@employer)
    get '/after-login'
    assert_response :success
    assert_includes response.body,@employer.id.to_s
    post identity_challenge_path,params: {otp: '000000'}
    assert_response :redirect
    assert_equal 1,@employer.sessions.count
  end
  def test_all_accounting_tabs_render_with_real_templates
    login(@employer)
    @fixture.entry(1000,'2026-01-02','Client receipt',@income)
    %w[ledger accounts rules imports reconcile reports workbooks audit].each do |tab|
      get workspace(tab)
      assert_response :success
      assert_includes response.body,'Books & accounting'
    end
    get dashboard_directory_path(employer_id: @employer.id)
    assert_response :success
    assert_includes response.body,'Organization sign-in'
    get dashboard_compliance_path(employer_id: @employer.id)
    assert_response :success
    assert_includes response.body,'Jurisdiction monitoring'
  end
  def test_unrelated_employer_and_payroll_roles_do_not_grant_accounting
    login(@manager.worker)
    get workspace
    assert_response :forbidden
    @manager.update!(accounting_access: 'reviewer')
    get workspace
    assert_response :success
    get dashboard_accounting_path(employer_id: @other.id,book_id: @book.id)
    assert_response :not_found
    post dashboard_accounting_transactions_path,params: {employer_id: @employer.id,book_id: @book.id,entry: {bank_account_id: @account.id,posted_on: '2026-01-02',amount: '100.00',description: 'Forbidden'}}
    assert_response :forbidden
    assert_equal 0,@book.transactions.count
  end
  def test_statement_upload_map_queue_commit_and_export
    login(@employer)
    post dashboard_accounting_imports_path,params: {employer_id: @employer.id,book_id: @book.id,bank_account_id: @account.id,pasted_statement: "Date,Description,Amount\n2026-01-02,=unsafe spreadsheet text,100.00\n"}
    assert_response :redirect
    record=LightekAccounting::Import.last
    post map_dashboard_accounting_import_path(record),params: {employer_id: @employer.id,book_id: @book.id,mapping: {date: '0',description: '1',amount: '2',date_format: 'iso',mode: 'signed'}}
    assert_response :redirect
    get workspace('imports',import_id: record.id)
    assert_response :success
    assert_includes response.body,'100.00'
    post commit_dashboard_accounting_import_path(record),params: {employer_id: @employer.id,book_id: @book.id}
    assert_response :redirect
    AccountingImportJob.new.perform(record.id,@employer.id,false)
    assert_equal 'committed',record.reload.status
    assert_equal 10000,@book.transactions.first.amount_cents
    get dashboard_accounting_export_path(employer_id: @employer.id,book_id: @book.id)
    assert_response :success
    assert_includes response.body,"'=unsafe spreadsheet text"
  end
  def test_csrf_blocks_financial_mutation
    login(@employer)
    Dashboard::AccountingController.allow_forgery_protection=true
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post dashboard_accounting_books_path,params: {employer_id: @employer.id,book: {name: 'forged'}}
    end
  ensure
    Dashboard::AccountingController.allow_forgery_protection=false
  end
end
class EnterpriseHttpChecks
  def test_worker_rechecks_revocation_and_scheduled_results_are_sealed
    login(@employer)
    @fixture.entry(10000,'2026-01-02','Income',@income)
    worker=LightekAccounting::Automation.new(book: @book,actor: @employer,next_run_at: Time.current)
    worker.data={'action'=>'reports','cadence'=>'daily'};worker.save!
    AccountingRefreshJob.new.perform(worker.id)
    assert_equal 10000,worker.reload.data.dig('latest','report','profit_cents')
    refute_includes worker.attributes.to_json,'profit_cents'
    @worker.update!(accounting_access: 'administrator')
    delegated=LightekAccounting::Automation.new(book: @book,actor: @worker.worker,next_run_at: Time.current)
    delegated.data={'action'=>'reports','cadence'=>'daily'};delegated.save!
    @worker.update!(active: false)
    AccountingRefreshJob.new.perform(delegated.id)
    refute delegated.reload.enabled?
    assert_nil delegated.data['latest']
  end
  def test_jurisdiction_sources_use_fixed_provider_contracts_and_do_not_claim_compliance
    require 'uri'
    LightekVault::Service.payload={'api_key'=>'fixture-source-key'}
    monitor=LightekCompliance::Monitor.create!(employer: @employer,actor: @employer,state: 'CA',provider: 'openstates',query: 'payroll',next_run_at: Time.current)
    calls=[]
    response={'results'=>[{'title'=>'Employment bill','identifier'=>'AB1','latest_action'=>{'description'=>'Introduced'},'openstates_url'=>'https://openstates.org/ca/bills/AB1'}]}
    callback=->(url,**options) { calls << [url,Marshal.load(Marshal.dump(options))];response }
    LightekIdentity::PublicHttp.stub(:json,callback) do
      snapshot=LightekCompliance::Sources.fetch(monitor)
      assert_equal 'legislative_activity',snapshot['items'].first['kind']
      assert_equal 'needs_review',snapshot['review_status']
      assert_includes calls.first[0],URI.encode_www_form_component('ocd-jurisdiction/country:us/state:ca/government')
      assert_equal 'fixture-source-key',calls.first[1].dig(:headers,'X-API-KEY')
      refute_includes snapshot.to_json,'fixture-source-key'
    end
    monitor.provider='ny_openleg'
    refute monitor.valid?
  end
end
class EnterpriseHttpChecks
  def test_required_mfa_has_an_enrollment_only_session_until_verified
    LightekIdentity::OrganizationPolicy.create!(employer: @employer,mfa_required: true)
    post session_path,params: {email_address: @employer.email_address,password: 'fixture-password'}
    assert_redirected_to identity_security_path
    pending=@employer.sessions.last
    assert pending.mfa_enrollment_only?
    assert_nil pending.mfa_verified_at
    get '/after-login'
    assert_redirected_to identity_security_path
    get identity_security_path
    assert_response :success
    post enroll_identity_security_path,params: {password: 'fixture-password'}
    assert_response :success
    factor=LightekIdentity::Factor.find_by!(user: @employer)
    secret=LightekIdentity::Sealed.open(factor.secret_box,context: "mfa:#{@employer.id}")['secret']
    post confirm_identity_security_path,params: {otp: LightekIdentity::Mfa.code(secret,Time.current.to_i/30)}
    assert_response :success
    refute pending.reload.mfa_enrollment_only?
    assert LightekIdentity::Mfa.fresh?(pending)
    get '/after-login'
    assert_response :success
  end
end
class EnterpriseHttpChecks
  def test_payroll_keeps_mfa_when_company_policy_is_relaxed
    LightekIdentity::OrganizationPolicy.create!(employer: @employer,mfa_required: false)
    post session_path,params: {email_address: @employer.email_address,password: 'fixture-password'}
    assert_response :redirect
    assert_equal 1,@employer.sessions.count
    post dashboard_people_pay_runs_path,params: {employer_id: @employer.id,pay_run: {period_start: '2026-01-01',period_end: '2026-01-15',pay_date: '2026-01-15'}}
    assert_redirected_to identity_security_path
    assert_equal 0,LightekPeople::PayRun.count
  end
end
class EnterpriseHttpChecks
  def test_hr_cannot_escalate_through_department_or_directory_principal
    @manager.update!(people_admin: true)
    @worker.update!(directory_principal: 'worker@ad.example.com')
    department=LightekPeople::Department.create!(employer: @employer,name: 'Privileged IT',code: 'PRIV')
    node=GatekeeperNode.create!(name: 'Privileged server',owner: @employer,ip_address: '198.51.100.2',ssh_user: 'root')
    LightekIdentity::ResourceGrant.create!(employer: @employer,subject: department,resource: node,permission: 'manage')
    login(@manager.worker)
    post dashboard_people_employments_path,params: {employer_id: @employer.id,record_id: @manager.id,employment: {department_id: department.id}}
    assert_response :forbidden
    assert_nil @manager.reload.department_id
    post dashboard_people_employments_path,params: {employer_id: @employer.id,record_id: @worker.id,employment: {title: 'Still employee',directory_principal: 'attacker@ad.example.com'}}
    assert_response :redirect
    assert_equal 'worker@ad.example.com',@worker.reload.directory_principal
  end
end
class EnterpriseHttpChecks
  def test_live_reconciliation_json_is_read_only_and_tenant_scoped
    login(@employer)
    row=@fixture.entry(10000,'2026-01-02','Cleared deposit')
    post dashboard_accounting_reconcile_path,params: {employer_id: @employer.id,book_id: @book.id,bank_account_id: @account.id,starts_on: '2026-01-01',ends_on: '2026-01-31',starting_amount: '1000.00',ending_amount: '1100.00',selected: [row.id.to_s],finalize: '0'},headers: {'Accept'=>'application/json'}
    assert_response :success
    assert_equal 0,JSON.parse(response.body)['cleared_difference_cents']
    assert_nil row.reload.reconciliation_id
    assert_equal 0,LightekAccounting::Reconciliation.count
  end
  def test_tax_endpoint_renders_the_report_with_reviewed_inputs
    login(@employer)
    post dashboard_accounting_tax_path,params: {employer_id: @employer.id,book_id: @book.id,tax_reviewed: '1',tax: {year: '2026',filing_status: 'single',profit: '100000.00'}}
    assert_response :success
    assert_includes response.body,'14,129.55'
    assert_includes response.body,'irs-1040es-2026-v1'
  end
end

class EnterpriseHttpChecks
  def test_it_admin_manages_directory_without_hr_or_finance_authority
    @worker.update!(directory_admin: true)
    department=LightekPeople::Department.create!(employer: @employer,name: 'Infrastructure operators',code: 'OPS')
    node=GatekeeperNode.create!(name: 'IT managed server',owner: @employer,ip_address: '198.51.100.2',ssh_user: 'root')
    LightekIdentity::OrganizationPolicy.create!(employer: @employer,mfa_required: false)
    assert LightekIdentity::Mfa.required?(@worker.worker)
    login(@worker.worker)
    get dashboard_directory_path(employer_id: @employer.id)
    assert_response :success
    assert_includes response.body,'IT directory administration'
    post dashboard_directory_member_path(@manager,employer_id: @employer.id),params: {password: 'fixture-password',membership: {directory_principal: 'manager@ad.example.com',department_id: department.id,payroll_access: 'administrator',directory_admin: true}}
    assert_response :redirect
    assert_equal 'manager@ad.example.com',@manager.reload.directory_principal
    assert_equal department.id,@manager.department_id
    refute @manager.directory_admin?
    assert_equal 'none',@manager.accounting_access
    post dashboard_directory_grants_path(employer_id: @employer.id),params: {password: 'fixture-password',subject_key: "employment:#{@manager.id}",resource_key: "server:#{node.id}",permission: 'read'}
    assert_response :redirect
    assert_includes LightekIdentity::Permissions.ids(@manager.worker,'GatekeeperNode','read'),node.id
    post dashboard_people_employments_path,params: {employer_id: @employer.id,record_id: @manager.id,employment: {title: 'IT may not edit HR'}}
    assert_response :forbidden
    get workspace
    assert_response :forbidden
    @worker.update!(directory_admin: false)
    post dashboard_directory_member_path(@manager,employer_id: @employer.id),params: {password: 'fixture-password',membership: {directory_principal: 'changed@ad.example.com'}}
    assert_response :forbidden
    assert_equal 'manager@ad.example.com',@manager.reload.directory_principal
  end
  def test_hr_cannot_appoint_it_or_mutate_directory_endpoint
    @manager.update!(people_admin: true)
    login(@manager.worker)
    post dashboard_people_employments_path,params: {employer_id: @employer.id,record_id: @manager.id,employment: {title: 'HR manager',directory_admin: true}}
    assert_response :redirect
    refute @manager.reload.directory_admin?
    post dashboard_directory_member_path(@worker,employer_id: @employer.id),params: {password: 'fixture-password',membership: {directory_principal: 'changed@ad.example.com'}}
    assert_response :forbidden
    assert_nil @worker.reload.directory_principal
  end
end

class EnterpriseHttpChecks
  def test_it_cannot_disable_the_required_authenticator
    @worker.update!(directory_admin: true)
    login(@worker.worker)
    post disable_identity_security_path,params: {password: 'fixture-password',otp: '000000'}
    assert_redirected_to identity_security_path
    assert LightekIdentity::Mfa.enabled?(@worker.worker)
  end
end
