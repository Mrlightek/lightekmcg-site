require_relative 'people_payroll_checks'
require 'action_controller/railtie'
require 'action_dispatch/testing/integration'
require 'tmpdir'
class PeopleHarness < Rails::Application
  config.root = Dir.mktmpdir('people-http-')
  config.eager_load = false
  config.secret_key_base = 'people-test-only-' * 8
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
  config.autoload_paths = []
end
PeopleHarness.initialize!
class ApplicationController < ActionController::Base
  helper_method :current_user
  before_action :authenticate
  def current_user = User.find_by(id: request.headers['X-Test-User'])
  def authenticate = (head(:unauthorized) unless current_user)
end
module Dashboard
  class SettingsHomeController < ApplicationController
    before_action :require_settings_operator!
    def require_settings_operator! = head(:forbidden)
  end
end
require ROOT.join('app/controllers/concerns/lightek_identity/sensitive_session')
require ROOT.join('app/controllers/dashboard/people_controller')
# This older header-auth fixture covers People workflows; enterprise_http_checks
# exercises the real session, MFA and enrollment boundary.
Dashboard::PeopleController.skip_before_action :sensitive_people!
Dashboard::PeopleController.layout false
PeopleHarness.routes.draw { eval(ROOT.join('config/routes/people.rb').read, binding) }
ApplicationController.prepend_view_path ROOT.join('app/views')
ApplicationController.helper(Module.new { def stylesheet_link_tag(*) = ''.html_safe })
class PeopleHttpChecks < ActionDispatch::IntegrationTest
  include PeopleHarness.routes.url_helpers
  def app = PeopleHarness
  def setup
    @fixture = PeoplePayrollChecks.new('unused')
    @fixture.setup
    @employer, @other, @worker, @manager, @preparer, @approver = %i[employer other worker manager preparer approver].map { |key| @fixture.instance_variable_get("@#{key}") }
    host! 'example.test'
  end
  def as(user) = {'X-Test-User'=>user.id.to_s}
  def test_directory_renders_and_department_creation_is_not_public
    get dashboard_people_path, headers: as(@employer)
    assert_response :success
    assert_includes response.body, 'Corporate directory'
    assert_includes response.body, 'Reports to'
    assert_includes response.body, 'Payroll responsibility'
    assert_equal 'no-store', response.headers['Cache-Control']
    default_count = LightekPeople::Department.count
    post dashboard_people_departments_path, params: {employer_id: @employer.id, department: {name: 'Research', code: 'research'}}, headers: as(@worker.worker)
    assert_response :forbidden
    assert_equal default_count, LightekPeople::Department.count
    post dashboard_people_departments_path, params: {employer_id: @employer.id, department: {name: 'Research', code: 'research'}}, headers: as(@employer)
    assert_response :redirect
    assert_equal 'RESEARCH', LightekPeople::Department.find_by!(name: 'Research').code
    get dashboard_people_path
    assert_response :unauthorized
  end
  def test_worker_only_sees_own_approved_statements_and_cannot_select_other_employer
    pay_run = @fixture.pay_run_fixture
    @fixture.add(pay_run)
    get dashboard_people_path(employer_id: @employer.id, tab: 'self'), headers: as(@worker.worker)
    assert_response :success
    refute_includes response.body, 'Net $'
    @fixture.approve(pay_run)
    get dashboard_people_path(employer_id: @employer.id, tab: 'self'), headers: as(@worker.worker)
    assert_response :success
    assert_includes response.body, 'Net $1,550.00'
    get dashboard_people_path(employer_id: @other.id, tab: 'self'), headers: as(@worker.worker)
    assert_response :not_found
    get dashboard_people_path(employer_id: @employer.id, tab: 'payroll'), headers: as(@manager.worker)
    assert_response :success
    refute_includes response.body, 'Gross pay (USD)'
    refute_includes response.body, '1,550.00'
  end
  def test_roster_administrator_cannot_grant_themselves_payroll
    @manager.update!(people_admin: true)
    post dashboard_people_employments_path, params: {employer_id: @employer.id, record_id: @manager.id,
      employment: {title: 'IT Manager', payroll_access: 'administrator'}}, headers: as(@manager.worker)
    assert_response :redirect
    assert_equal 'none', @manager.reload.payroll_access
    assert_equal 'IT Manager', @manager.title
  end
  def test_foreign_record_ids_cannot_be_updated
    foreign = LightekPeople::Department.create!(employer: @other, name: 'Other department', code: 'other')
    post dashboard_people_departments_path, params: {employer_id: @employer.id, record_id: foreign.id,
      department: {name: 'Stolen', code: 'stolen'}}, headers: as(@employer)
    assert_response :not_found
    assert_equal 'Other department', foreign.reload.name
  end
  def test_payroll_forms_render_and_reviewed_amounts_are_required
    get dashboard_people_path(employer_id: @employer.id, tab: 'payroll'), headers: as(@preparer.worker)
    assert_response :success
    refute_includes response.body, 'Restricted API key'
    post dashboard_people_pay_runs_path, params: {employer_id: @employer.id,
      pay_run: {period_start: Date.current - 14, period_end: Date.current, pay_date: Date.current}}, headers: as(@preparer.worker)
    assert_response :redirect
    pay_run = LightekPeople::PayRun.last
    get dashboard_people_path(employer_id: @employer.id, tab: 'payroll', run_id: pay_run.id), headers: as(@preparer.worker)
    assert_response :success
    assert_includes response.body, 'Tax calculation / review reference'
    post dashboard_people_pay_statement_path(pay_run), params: {employer_id: @employer.id,
      statement: {employment_id: @worker.id, gross_amount: '2000.00', tax_amount: '400.00', employer_tax_amount: '153.00', other_deductions_amount: '50.00', tax_reference: 'reviewed'}}, headers: as(@preparer.worker)
    assert_response :redirect
    assert_equal 0, pay_run.pay_statements.count
    post dashboard_people_pay_statement_path(pay_run), params: {employer_id: @employer.id, tax_reviewed: '1',
      statement: {employment_id: @worker.id, gross_amount: '2000.00', tax_amount: '400.00', employer_tax_amount: '153.00', other_deductions_amount: '50.00', tax_reference: 'reviewed'}}, headers: as(@preparer.worker)
    assert_response :redirect
    assert_equal 155_000, pay_run.pay_statements.first.net_cents
    get export_dashboard_people_pay_run_path(pay_run, employer_id: @employer.id), headers: as(@worker.worker)
    assert_response :forbidden
    get export_dashboard_people_pay_run_path(pay_run, employer_id: @employer.id), headers: as(@approver.worker)
    assert_response :success
    assert_includes response.body, '155000'
  end
  def test_benefit_plan_and_self_election_workflow
    post dashboard_people_benefits_path, params: {employer_id: @employer.id,
      benefit: {name: 'Health', category: 'health', employee_amount: '100.00', employer_amount: '200.00', published: '1', deduction_treatment: 'post_tax'}}, headers: as(@preparer.worker)
    assert_response :redirect
    plan = LightekPeople::BenefitPlan.last
    assert_equal 10_000, plan.employee_cents
    post dashboard_people_enrollments_path, params: {employer_id: @employer.id, employment_id: @worker.id, benefit_plan_id: plan.id}, headers: as(@manager.worker)
    assert_response :forbidden
    post dashboard_people_enrollments_path, params: {employer_id: @employer.id, employment_id: @worker.id, benefit_plan_id: plan.id}, headers: as(@worker.worker)
    assert_response :redirect
    assert_equal 1, @worker.benefit_enrollments.count
    get dashboard_people_path(employer_id: @employer.id, tab: 'self'), headers: as(@worker.worker)
    assert_response :success
    assert_includes response.body, 'Enrolled'
    get dashboard_people_path(employer_id: @employer.id, tab: 'benefits'), headers: as(@preparer.worker)
    assert_response :success
    assert_includes response.body, 'Employee contribution (USD)'
  end
end
class PeopleHttpChecks
  def test_csrf_blocks_mutation_without_token
    Dashboard::PeopleController.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post dashboard_people_departments_path, params: {employer_id: @employer.id, department: {name: 'Forged', code: 'fake'}}, headers: as(@employer)
    end
    assert_equal 0, LightekPeople::Department.count
  ensure
    Dashboard::PeopleController.allow_forgery_protection = false
  end
  def test_bank_setup_only_uses_the_authenticated_workers_membership
    require 'minitest/mock'
    captured = nil
    adapter = Object.new
    adapter.define_singleton_method(:onboard!) do |**args|
      captured = args[:destination]
      'https://accounts.stripe.com/r/fixture'
    end
    DymondBank::WorkforcePayouts.stub(:new, adapter) do
      post dashboard_people_bank_setup_path, params: {employer_id: @employer.id, employment_id: @manager.id}, headers: as(@worker.worker)
      assert_response :redirect
      assert_equal 'https://accounts.stripe.com/r/fixture', response.location
      assert_equal @worker.id, captured.employment_id
      assert_nil @manager.reload.payout_destination
    end
  end
end
class PeopleHttpChecks
  def test_former_member_keeps_own_statements_but_loses_delegated_authority
    pay_run = @fixture.pay_run_fixture
    @fixture.add(pay_run)
    @fixture.approve(pay_run)
    @worker.update!(active: false, ends_on: Date.current - 1, payroll_access: 'administrator', people_admin: true)
    get dashboard_people_path(employer_id: @employer.id, tab: 'self'), headers: as(@worker.worker)
    assert_response :success
    assert_includes response.body, 'Net $1,550.00'
    get export_dashboard_people_pay_run_path(pay_run, employer_id: @employer.id), headers: as(@worker.worker)
    assert_response :forbidden
    get dashboard_people_path(employer_id: @employer.id), headers: as(@worker.worker)
    assert_response :success
    refute_includes response.body, 'Manage team members'
    refute_includes response.body, @manager.worker.email_address
  end
end
