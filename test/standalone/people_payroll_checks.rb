# Pure ActiveRecord checks; no private engines, real provider calls or bank data.
require 'active_record'
require 'active_support/all'
require 'minitest/autorun'
require 'pathname'
ROOT = Pathname.new(File.expand_path('../..', __dir__))
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
ActiveRecord::Base.establish_connection(ENV.fetch('PEOPLE_DATABASE_URL', 'sqlite3::memory:'))
ActiveRecord::Migration.verbose = false
if ActiveRecord::Base.connection.adapter_name == 'SQLite'
  ActiveRecord::ConnectionAdapters::TableDefinition.class_eval { alias_method :jsonb, :json }
end
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :email_address; t.string :role; t.string :first_name }
end
source = ROOT.join('db/migrate/20261113160000_create_lightek_people_and_payroll.rb').read.gsub('Migration[8.0]', "Migration[#{ActiveRecord::VERSION::MAJOR >= 8 ? '8.0' : '7.2'}]")
eval(source, TOPLEVEL_BINDING)
CreateLightekPeopleAndPayroll.new.migrate(:up)
class User < ApplicationRecord
  def full_name = first_name.presence || email_address
end
Dir[ROOT.join('app/models/lightek_people/*.rb')].sort.each { |f| require f }
module LightekVault
  class Secret
    class << self
      attr_accessor :entries
      def find_by(slug:) = entries&.fetch(slug, nil)
    end
  end
  class Service
    class AccessDenied < StandardError; end
    class << self
      attr_accessor :payload, :checkouts, :writes
      def checkout!(**args)
        self.checkouts ||= []
        checkouts << args
        raise AccessDenied unless payload
        Marshal.load(Marshal.dump(payload))
      end
      def store!(**args)
        self.writes ||= []
        writes << args.deep_dup
      end
    end
  end
end
require ROOT.join('app/services/dymond_bank/workforce_payouts')
%w[access payroll disbursements].each { |f| require ROOT.join("app/services/lightek_people/#{f}") }
class PeoplePayrollChecks < Minitest::Test
  def setup
    [LightekPeople::AuditEvent, LightekPeople::PayStatement, LightekPeople::PayRun, LightekPeople::BenefitEnrollment,
      LightekPeople::BenefitPlan, LightekPeople::PayoutDestination, LightekPeople::PayoutSender].each(&:delete_all)
    LightekPeople::Employment.update_all(manager_id: nil)
    LightekPeople::Employment.delete_all
    LightekPeople::Department.update_all(parent_id: nil)
    LightekPeople::Department.delete_all
    User.delete_all
    @employer = user('owner', 'white_label')
    @other = user('unrelated', 'client')
    @manager = hire('manager', level: 'manager')
    @lead = hire('lead', level: 'team_lead', manager: @manager)
    @worker = hire('worker', manager: @lead)
    @preparer = hire('preparer', payroll_access: 'preparer')
    @approver = hire('approver', payroll_access: 'approver')
    @owner_access = access(@employer)
    @preparer_access = access(@preparer.worker)
    @approver_access = access(@approver.worker)
    LightekVault::Service.payload = {'employer_id'=>@employer.id.to_s, 'financial_account_ref'=>'fa_employer', 'secret_key'=>'rk_test_fixture'}
    LightekVault::Service.checkouts = []
    LightekPeople::PayoutSender.create!(employer: @employer, financial_account_ref: 'fa_employer')
  end
  def user(name, role = 'employee') = User.create!(email_address: "#{name}@example.test", first_name: name, role: role)
  def hire(name, **values)
    LightekPeople::Employment.create!(employer: @employer, worker: user(name), title: name.humanize, starts_on: Date.current - 60, **values)
  end
  def access(actor) = LightekPeople::Access.new(actor: actor, employer: @employer)
  def pay_run_fixture
    LightekPeople::PayRun.create!(employer: @employer, prepared_by: @preparer.worker, period_start: Date.current - 14, period_end: Date.current, pay_date: Date.current)
  end
  def add(run, worker = @worker, overrides = {})
    LightekPeople::Payroll.new(access: @preparer_access).add!(run: run, employment: worker,
      values: {gross_cents: 200_000, tax_cents: 40_000, employer_tax_cents: 15_300, other_deductions_cents: 5_000, tax_reference: 'Reviewed payroll calculation #123'}.merge(overrides))
  end
  def approve(run)
    LightekPeople::Payroll.new(access: @approver_access).approve!(run: run)
  end
  def destination(worker = @worker)
    worker.create_payout_destination!(recipient_ref: "acct_worker#{worker.id}", capability_status: 'active')
  end
  class Provider
    attr_accessor :calls, :response, :failure
    def initialize(statement)
      @calls = []
      @response = {'id'=>"poi_statement#{statement.id}", 'status'=>'requires_action',
        'from'=>{'financial_account'=>'fa_employer', 'debited'=>{'value'=>statement.net_cents + 25,'currency'=>'usd'}},
        'to'=>{'recipient'=>statement.employment.payout_destination.recipient_ref, 'credited'=>{'value'=>statement.net_cents,'currency'=>'usd'}},
        'amount'=>{'value'=>statement.net_cents,'currency'=>'usd'}, 'estimated_fees'=>[{'amount'=>{'value'=>25,'currency'=>'usd'}}],
        'next_action'=>{'type'=>'confirm','confirm'=>{'reason'=>'manually_requested'}}}
    end
    def prepare!(line)
      @calls << [:prepare, line.id]
      raise failure if failure
      @response.deep_dup
    end
    def retrieve!(ref)
      @calls << [:retrieve, ref]
      @response.deep_dup
    end
    def confirm!(line)
      @calls << [:confirm, line.id]
      @response['status'] = 'pending'
      @response.deep_dup
    end
  end
  def test_department_tree_and_reporting_chain_are_scoped_and_acyclic
    parent = LightekPeople::Department.create!(employer: @employer, name: 'Technology', code: 'tech')
    child = LightekPeople::Department.create!(employer: @employer, parent: parent, name: 'IT', code: 'it')
    parent.parent = child
    refute parent.valid?
    refute LightekPeople::Department.new(employer: @other, name: 'Foreign', code: 'f', parent: child).valid?
    @manager.manager = @worker
    refute @manager.valid?
    @worker.manager = @worker
    refute @worker.valid?
    @lead.manager = @worker
    refute @lead.valid?
    @manager.reload.update(level: 'individual_contributor')
    assert @manager.errors.any?
  end
  def test_managers_see_reporting_tree_without_payroll_authority
    manager_access = access(@manager.worker)
    assert_equal [@manager.id,@lead.id,@worker.id].sort, manager_access.roster.pluck(:id).sort
    assert_equal [@lead.id,@worker.id].sort, access(@lead.worker).roster.pluck(:id).sort
    assert_equal [@worker.id], access(@worker.worker).roster.pluck(:id)
    refute manager_access.payroll?
    assert_raises(LightekPeople::Access::Denied) { manager_access.require!(:approve) }
    assert_raises(LightekPeople::Access::Denied) { manager_access.require!(:people) }
    assert_raises(LightekPeople::Access::Denied) { access(@other) }
    assert_equal [@other.id], LightekPeople::Access.employers_for(@other).pluck(:id)
  end
  def test_explicit_payroll_roles_and_revocation
    assert @preparer_access.payroll?(:prepare)
    refute @preparer_access.payroll?(:approve)
    assert @approver_access.payroll?(:release)
    refute @approver_access.payroll?(:prepare)
    @approver.update!(active: false)
    assert_raises(LightekPeople::Access::Denied) { @approver_access.require!(:release) }
  end
  def test_cross_employer_reporting_and_benefits_are_rejected
    department = LightekPeople::Department.create!(employer: @other, name: 'Accounting', code: 'acct')
    @worker.department = department
    refute @worker.valid?
    plan = LightekPeople::BenefitPlan.create!(employer: @other, name: 'Foreign health', category: 'health')
    refute LightekPeople::BenefitEnrollment.new(employment: @worker, benefit_plan: plan, starts_on: Date.current).valid?
  end
  def test_gross_net_benefits_and_employer_liabilities_snapshot
    plan = LightekPeople::BenefitPlan.create!(employer: @employer, name: 'Health', category: 'health', employee_cents: 12_000, employer_cents: 30_000, deduction_treatment: 'pre_tax')
    @worker.benefit_enrollments.create!(benefit_plan: plan, starts_on: Date.current - 5)
    pay_run = pay_run_fixture
    line = add(pay_run)
    assert_equal 143_000, line.net_cents
    assert_equal 30_000, line.employer_benefit_cents
    assert_equal 15_300, line.employer_tax_cents
    assert_equal 'pre_tax', line.snapshot['benefits'][0]['treatment']
    plan.update!(employee_cents: 1)
    assert_equal 12_000, line.reload.benefit_cents
    approve(pay_run)
    assert_equal 'approved', line.reload.status
    assert_equal 'fa_employer', pay_run.reload.financial_account_ref
    assert_raises(LightekPeople::Payroll::Invalid) { add(pay_run) }
    assert_equal 143_000, line.reload.net_cents
    assert_equal 1, LightekPeople::AuditEvent.where(action: 'pay_run_approved').count
  end
  def test_independent_approval_and_negative_net_guard
    pay_run = pay_run_fixture
    assert_raises(ActiveRecord::RecordInvalid) { add(pay_run, @worker, tax_cents: 300_000) }
    assert_equal 0, pay_run.pay_statements.count
    add(pay_run)
    @preparer.update!(payroll_access: 'administrator')
    assert_raises(LightekPeople::Payroll::Invalid) { LightekPeople::Payroll.new(access: access(@preparer.worker)).approve!(run: pay_run) }
    assert_equal 'draft', pay_run.reload.status
    empty_run = LightekPeople::PayRun.create!(employer: @employer, prepared_by: @preparer.worker, period_start: Date.current - 7, period_end: Date.current, pay_date: Date.current)
    assert_raises(LightekPeople::Payroll::Invalid) { approve(empty_run) }
  end
  def test_foreign_employer_run_cannot_be_changed
    foreign = LightekPeople::PayRun.create!(employer: @other, prepared_by: @other, period_start: Date.current, period_end: Date.current, pay_date: Date.current)
    assert_raises(LightekPeople::Access::Denied) { add(foreign) }
  end
  def test_provider_timeout_has_durable_attempt_and_retries_same_statement
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    destination
    provider = Provider.new(line)
    provider.failure = DymondBank::WorkforcePayouts::ProviderError.new('timeout')
    service = LightekPeople::Disbursements.new(access: @approver_access, adapter: provider)
    assert_raises(DymondBank::WorkforcePayouts::ProviderError) { service.perform!(statement: line, action: 'prepare') }
    assert line.reload.attempted_at
    assert_nil line.provider_ref
    provider.failure = nil
    service.perform!(statement: line, action: 'prepare')
    assert_equal 'review', line.reload.status
    service.perform!(statement: line, action: 'prepare')
    assert_equal 2, provider.calls.count { |call| call[0] == :prepare }
    service.perform!(statement: line, action: 'confirm', review_digest: LightekPeople::Disbursements.quote_digest(line.reload.quote))
    service.perform!(statement: line, action: 'confirm', review_digest: LightekPeople::Disbursements.quote_digest(line.reload.quote))
    assert_equal 1, provider.calls.count { |call| call[0] == :confirm }
    assert_equal 'pending', line.reload.status
    assert_raises(LightekPeople::Payroll::Invalid) { LightekPeople::Payroll.new(access: @approver_access).cancel!(run: pay_run) }
  end
  def test_old_unresolved_attempt_fails_closed
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    destination
    line.update!(attempted_at: 24.hours.ago)
    provider = Provider.new(line)
    assert_raises(LightekPeople::Payroll::Invalid) { LightekPeople::Disbursements.new(access: @approver_access, adapter: provider).perform!(statement: line, action: 'prepare') }
    assert_empty provider.calls
  end
  def test_provider_mismatch_never_releases_and_fee_changes_require_rereview
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    destination
    provider = Provider.new(line)
    service = LightekPeople::Disbursements.new(access: @approver_access, adapter: provider)
    service.perform!(statement: line, action: 'prepare')
    provider.response['estimated_fees'] = [{'amount'=>{'value'=>75,'currency'=>'usd'}}]
    assert_raises(LightekPeople::Payroll::Invalid) { service.perform!(statement: line, action: 'confirm', review_digest: LightekPeople::Disbursements.quote_digest(line.reload.quote)) }
    assert_equal 75, line.reload.quote.dig('fees',0,'amount','value')
    provider.response['from']['financial_account'] = 'fa_foreign'
    assert_raises(LightekPeople::Payroll::Invalid) { service.perform!(statement: line, action: 'confirm', review_digest: LightekPeople::Disbursements.quote_digest(line.reload.quote)) }
    assert_equal 0, provider.calls.count { |call| call[0] == :confirm }
  end
  def test_future_pay_date_and_preparer_cannot_release
    pay_run = pay_run_fixture
    pay_run.update!(pay_date: Date.tomorrow)
    line = add(pay_run)
    approve(pay_run)
    destination
    provider = Provider.new(line)
    assert_raises(LightekPeople::Payroll::Invalid) { LightekPeople::Disbursements.new(access: @approver_access, adapter: provider).perform!(statement: line, action: 'prepare') }
    assert_raises(LightekPeople::Access::Denied) { LightekPeople::Disbursements.new(access: @preparer_access, adapter: provider).perform!(statement: line, action: 'prepare') }
    assert_empty provider.calls
  end
  def test_only_correct_employer_vault_credentials_can_be_read
    adapter = DymondBank::WorkforcePayouts.new(employer: @employer)
    assert_equal 'fa_employer', adapter.financial_account_ref
    assert_equal "workforce-payouts-#{@employer.id}", LightekVault::Service.checkouts.last[:slug]
    LightekVault::Service.payload['employer_id'] = @other.id.to_s
    assert_raises(DymondBank::WorkforcePayouts::Unavailable) { adapter.financial_account_ref }
  end
  def test_ended_benefits_do_not_apply_and_history_is_preserved
    plan = LightekPeople::BenefitPlan.create!(employer: @employer, name: 'Health', category: 'health', employee_cents: 10_000)
    election = @worker.benefit_enrollments.create!(benefit_plan: plan, starts_on: Date.current - 20, ends_on: Date.current)
    refute election.covers?(Date.current)
    line = add(pay_run_fixture)
    assert_equal 155_000, line.net_cents
    @worker.benefit_enrollments.create!(benefit_plan: plan, starts_on: Date.current)
    assert_equal 2, @worker.benefit_enrollments.count
  end
end
class PeoplePayrollChecks
  def test_approved_amounts_and_period_are_immutable
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    refute line.update(gross_cents: 300_000, net_cents: 255_000)
    refute pay_run.update(period_start: Date.current - 30)
    assert_equal 200_000, line.reload.gross_cents
    assert_equal Date.current - 14, pay_run.reload.period_start
    assert_raises(ActiveRecord::RecordInvalid) { pay_run_fixture }
  end
  def test_sender_binding_cannot_be_shared_by_employers
    other_sender = LightekPeople::PayoutSender.new(employer: @other, financial_account_ref: 'fa_employer')
    refute other_sender.valid?
    assert_raises(LightekPeople::Access::Denied) do
      DymondBank::WorkforcePayouts.store!(access: @preparer_access, secret_key: 'rk_test_fixture', financial_account_ref: 'fa_other')
    end
  end
  def test_posted_status_does_not_claim_bank_delivery_and_returns_are_visible
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    destination
    provider = Provider.new(line)
    service = LightekPeople::Disbursements.new(access: @approver_access, adapter: provider)
    service.perform!(statement: line, action: 'prepare')
    provider.response['status'] = 'posted'
    service.perform!(statement: line, action: 'refresh')
    assert_equal 'posted', line.reload.status
    provider.response['outbound_status'] = 'returned'
    service.perform!(statement: line, action: 'refresh')
    assert_equal 'returned', line.reload.status
    service.perform!(statement: line, action: 'confirm', review_digest: LightekPeople::Disbursements.quote_digest(line.reload.quote))
    assert_equal 0, provider.calls.count { |c| c[0] == :confirm }
  end
end
class WorkforceAdapterChecks < PeoplePayrollChecks
  # Reuse database setup without inheriting all checks a second time.
  def self.runnable_methods = super.grep(/test_adapter_/)
  class Adapter < DymondBank::WorkforcePayouts
    attr_reader :requests
    attr_accessor :bad_url
    def initialize(**args)
      super
      @requests = []
    end
    def request(method, path, body = nil, key: nil)
      @requests << {method: method, path: path, body: body, key: key}
      case path
      when '/v2/core/accounts'
        {'id'=>'acct_recipient_fixture'}
      when '/v2/core/account_links'
        {'url'=>bad_url || 'https://accounts.stripe.com/r/fixture'}
      when %r{/v2/core/accounts/}
        {'configuration'=>{'recipient'=>{'capabilities'=>{'bank_accounts'=>{'ach'=>{'status'=>'active'}}}}}}
      when '/v2/money_management/payout_intents'
        {'id'=>'poi_fixture'}
      else
        raise "Unexpected path #{path}"
      end
    end
  end
  def test_adapter_hosted_onboarding_and_payout_contract
    adapter = Adapter.new(employer: @employer)
    dest = @worker.create_payout_destination!
    url = adapter.onboard!(destination: dest, return_url: 'https://example.test/return', refresh_url: 'https://example.test/refresh')
    assert_equal 'https://accounts.stripe.com/r/fixture', url
    assert_equal 'acct_recipient_fixture', dest.reload.recipient_ref
    account_request = adapter.requests.find { |r| r[:path] == '/v2/core/accounts' }
    assert_equal @worker.worker.email_address, account_request.dig(:body,'contact_email')
    refute account_request[:body].key?('bank_account')
    link_request = adapter.requests.find { |r| r[:path] == '/v2/core/account_links' }
    assert_equal ['recipient'], link_request.dig(:body,'use_case','account_onboarding','configurations')
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    adapter.prepare!(line)
    request = adapter.requests.last
    assert_equal 'manual', request.dig(:body,'confirmation_method')
    assert_equal 'fa_employer', request.dig(:body,'from','financial_account')
    assert_equal line.net_cents, request.dig(:body,'amount','value')
    assert_equal "workforce-statement-#{line.id}-v1", request[:key]
    assert_equal 'acct_recipient_fixture', request.dig(:body,'to','recipient')
    refute request[:body].to_s.include?('account_number')
    adapter.bad_url = 'https://accounts.stripe.com.evil.test/steal'
    assert_raises(DymondBank::WorkforcePayouts::ProviderError) do
      adapter.onboard!(destination: dest, return_url: 'https://example.test/return', refresh_url: 'https://example.test/refresh')
    end
  end
end
if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
  class PeoplePayrollChecks
    def test_concurrent_preparation_creates_one_provider_payout
      pay_run = pay_run_fixture
      line = add(pay_run)
      approve(pay_run)
      destination
      provider = Provider.new(line)
      actor_id, employer_id, statement_id = @approver.worker_id, @employer.id, line.id
      ready, start = Queue.new, Queue.new
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            policy = LightekPeople::Access.new(actor: User.find(actor_id), employer: User.find(employer_id))
            ready << true
            start.pop
            LightekPeople::Disbursements.new(access: policy, adapter: provider).perform!(statement: LightekPeople::PayStatement.find(statement_id), action: 'prepare')
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:value)
      assert_equal 1, provider.calls.count { |c| c[0] == :prepare }
      assert_equal "poi_statement#{line.id}", line.reload.provider_ref
      assert_equal 'review', line.status
    end
  end
end
class PeoplePayrollChecks
  def test_payment_creation_cannot_hide_durable_attempt_inside_outer_transaction
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    destination
    provider = Provider.new(line)
    ActiveRecord::Base.transaction do
      assert_raises(LightekPeople::Payroll::Invalid) do
        LightekPeople::Disbursements.new(access: @approver_access, adapter: provider).perform!(statement: line, action: 'prepare')
      end
    end
    assert_empty provider.calls
    assert_nil line.reload.attempted_at
  end
end
class PeoplePayrollChecks
  def test_stale_browser_quote_cannot_authorize_new_fees
    pay_run = pay_run_fixture
    line = add(pay_run)
    approve(pay_run)
    destination
    provider = Provider.new(line)
    service = LightekPeople::Disbursements.new(access: @approver_access, adapter: provider)
    service.perform!(statement: line, action: 'prepare')
    old_digest = LightekPeople::Disbursements.quote_digest(line.reload.quote)
    provider.response['estimated_fees'] = [{'amount'=>{'value'=>500,'currency'=>'usd'}}]
    service.perform!(statement: line, action: 'refresh')
    assert_raises(LightekPeople::Payroll::Invalid) { service.perform!(statement: line, action: 'confirm', review_digest: old_digest) }
    assert_equal 0, provider.calls.count { |c| c[0] == :confirm }
    service.perform!(statement: line, action: 'confirm', review_digest: LightekPeople::Disbursements.quote_digest(line.reload.quote))
    assert_equal 1, provider.calls.count { |c| c[0] == :confirm }
  end
end
