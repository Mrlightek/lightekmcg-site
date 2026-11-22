# frozen_string_literal: true

require 'active_record'
require 'active_record/connection_adapters/sqlite3_adapter'
require 'active_support/testing/time_helpers'
require 'minitest/autorun'
require 'minitest/mock'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Migration.verbose = false
# The onboarding evidence uses JSONB in PostgreSQL and portable JSON semantics.
ActiveRecord::ConnectionAdapters::SQLite3::TableDefinition.alias_method :jsonb, :json
ActiveRecord::Schema.define do
  create_table(:users) do |t|
    t.string :role
    t.string :email_address
    t.bigint :agency_id
    t.datetime :access_suspended_at
    t.boolean :password_setup_required, default: false
  end
  create_table(:lightek_commerce_orders) do |t|
    t.string :status
    t.string :purpose
    t.string :fulfillment_reference
    t.string :customer_email
    t.bigint :site_id
    t.bigint :hosting_owner_id
    t.datetime :paid_at
    t.datetime :deleted_at
  end
  create_table(:lightek_agency_trials) do |t|
    t.bigint :order_id
    t.bigint :operator_id
    t.bigint :prospect_id
    t.bigint :billing_site_id
    t.datetime :activated_at
    t.datetime :paid_through
    t.datetime :created_at
  end
  create_table(:lightek_agency_trial_requests) do |t|
    t.bigint :site_id
    t.bigint :operator_id
    t.string :email_address
    t.datetime :confirmed_at
  end
  create_table(:lightek_mail_domains) { |t| t.string :name }
  create_table(:lightek_mail_accounts) do |t|
    t.bigint :user_id
    t.bigint :domain_id
    t.boolean :brand_member
    t.boolean :enabled
  end
  create_table(:marlon_tickets) do |t|
    t.references :submitted_by
    t.json :extra_fields
    t.timestamps
  end
  create_table(:marlon_ticket_events) do |t|
    t.references :ticket
    t.string :action
    t.timestamps
  end
  create_table(:notifications) do |t|
    t.references :recipient, polymorphic: true
    t.references :subject, polymorphic: true
    t.string :category
    t.string :title
    t.string :body
    t.string :url
  end
end

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
class User < ApplicationRecord
  def white_label? = role == 'white_label'
end
module LightekCommerce
  class Order < ApplicationRecord
    self.table_name = 'lightek_commerce_orders'
    def site = site_id
  end
  module Installations
    def self.ready?(order) = order.status == 'fulfilled' && order.paid_at?
    def self.member_move_pending?(_order) = false
  end
end
module Marlon
  class Ticket < ApplicationRecord
    self.table_name = 'marlon_tickets'
    belongs_to :submitted_by, class_name: 'User'
    has_many :events, class_name: 'Marlon::TicketEvent'
  end
  class TicketEvent < ApplicationRecord
    self.table_name = 'marlon_ticket_events'
  end
end
module NevaehCustomerService
  module Cases
    CUSTOMER_REPLY = 'Customer reply'
    STAFF_REPLY = 'Support reply'
    def self.scope = Marlon::Ticket.all
    def self.customer_scope(actor) = scope.where(submitted_by: actor)
    def self.installations(actor) = LightekCommerce::Order.where(hosting_owner_id: actor.id)
  end
end
module LightekPwa
  module Policy
    def self.platform_operator(_site) = nil
  end
end
module LightekAgency
  class Trial < ApplicationRecord
    self.table_name = 'lightek_agency_trials'
    ORDER_PURPOSE = 'agency_membership'
    belongs_to :operator, class_name: 'User'
    belongs_to :prospect, class_name: 'User'
    belongs_to :order, class_name: 'LightekCommerce::Order'
    def paid_access? = paid_through.future? && order.status == 'fulfilled'
  end
  class TrialRequest < ApplicationRecord
    self.table_name = 'lightek_agency_trial_requests'
  end
end
module LightekPeople
  class LifecycleCase
    def self.table_exists? = false
  end
end
module LightekMail
  class Domain < ApplicationRecord
    self.table_name = 'lightek_mail_domains'
  end
  class Account < ApplicationRecord
    self.table_name = 'lightek_mail_accounts'
    scope :mailboxes, -> { all }
    belongs_to :user
    belongs_to :domain
    def sending_ready? = enabled?
  end
end
module DymondDash
  class Notification < ApplicationRecord
    belongs_to :recipient, polymorphic: true
    belongs_to :subject, polymorphic: true
  end
end
class LightekEmailProvisioningService
  DOMAIN = 'lightekmcg.com'
  class Unavailable < StandardError; end
  def self.provision_for_paid_agency!(user, expected_email:)
    raise 'Email identity changed' unless user.email_address == expected_email

    LightekMail::Account.create!(user: user, domain: LightekMail::Domain.find_by!(name: DOMAIN),
      brand_member: true, enabled: true)
  end
end
module Rails
  def self.application = self
  def self.routes = self
  def self.url_helpers = self
  def self.dashboard_agencies_path = '/dashboard/agencies'
  def self.installation_path(order) = "/my/installations/#{order.id}"
end

require_relative '../../db/migrate/20261122220000_create_nevaeh_agency_onboarding'
CreateNevaehAgencyOnboarding.new.migrate(:up)
require_relative '../../db/migrate/20261122230000_create_nevaeh_resolution_experiments'
CreateNevaehResolutionExperiments.new.migrate(:up)
require_relative '../../app/models/nevaeh_onboarding_case'
require_relative '../../app/models/nevaeh_onboarding_playbook'
require_relative '../../app/services/lightek_people/lifecycle_access'
require_relative '../../app/services/nevaeh_onboarding/standing_assignment'
require_relative '../../app/services/nevaeh_onboarding/improvement'

require_relative '../../app/models/nevaeh_resolution_playbook'
require_relative '../../app/models/nevaeh_resolution_observation'
require_relative '../../app/services/nevaeh_improvement/cycle'
require_relative '../../app/services/nevaeh_improvement/agency'
require_relative '../../app/services/nevaeh_improvement/purchased_service'

class NevaehOnboardingChecks < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  Assignment = NevaehOnboarding::StandingAssignment
  Improvement = NevaehOnboarding::Improvement

  def setup
    LightekMail::Domain.find_or_create_by!(name: 'lightekmcg.com')
    @operator = User.create!(role: 'super_admin')
  end

  def test_paid_agency_reminder_and_evidence_based_completion
    trial = paid_trial(paid_at: 30.hours.ago)
    entry = Assignment.start!(trial)
    Assignment.advance!(entry)
    Assignment.advance!(Assignment.start!(trial))
    assert_equal 1, NevaehOnboardingCase.where(order: trial.order).count
    assert_equal 1, DymondDash::Notification.where(subject: trial.order).count
    assert_equal 'waiting_for_dashboard', entry.reload.blocker
    assert entry.dashboard_escalated_at?
    refute entry.completed_at?

    # Mailbox proof for a different storefront cannot be reused.
    proof = LightekAgency::TrialRequest.create!(site_id: 2, operator_id: @operator.id,
      email_address: trial.prospect.email_address, confirmed_at: Time.current)
    Assignment.record_dashboard!(trial.prospect)
    Assignment.advance!(entry)
    assert_equal 'email_verification_required', entry.reload.blocker
    refute entry.completed_at?

    proof.update!(site_id: trial.billing_site_id)
    Assignment.advance!(entry)
    assert entry.reload.completed_at?
    assert entry.mailbox_at?
    assert entry.dashboard_escalated_at?
    assert_nil entry.escalated_at
    assert_equal 1, LightekMail::Account.where(user: trial.prospect).count
  end

  def test_refund_or_ownership_change_does_not_finish_an_existing_case
    trial = paid_trial
    entry = Assignment.start!(trial)
    trial.order.update!(status: 'refunded')
    Assignment.advance!(entry.reload)
    assert entry.closed_at?
    refute entry.completed_at?
    assert_nil Assignment.start!(trial.reload)
    assert_equal 'eligibility_changed', entry.blocker
  end

  def test_holdout_replay_operator_authority_and_recursive_regression_retention
    12.times do |number|
      entry = Assignment.start!(paid_trial(paid_at: (130 - number).hours.ago))
      entry.update!(dashboard_at: entry.paid_at + 30.hours)
    end
    improvement = Improvement.new(@operator)
    assert_difference_in_playbooks(1) { improvement.evaluate! }
    proposal = NevaehOnboardingPlaybook.find_by!(operator: @operator, status: 'proposed')
    assert_equal 48, proposal.escalate_after_hours
    assert_equal 6, proposal.evaluation.fetch('holdout_ids').size
    assert_raises(ActiveRecord::RecordNotFound) { Improvement.new(User.create!(role: 'super_admin')).promote!(proposal.id) }
    improvement.promote!(proposal.id)
    assert_equal 'active', proposal.reload.status

    played = %w[control candidate].to_h do |group|
      rows = Array.new(6) do
        entry = Assignment.start!(paid_trial(paid_at: 80.hours.ago))
        timing = group == 'control' ? 24 : 48
        entry.update!(evaluation_cohort: group, dashboard_escalated_at: entry.paid_at + timing.hours)
        entry.id
      end
      [group, rows]
    end

    improvement.evaluate!
    proposal.reload
    assert_equal 'rolled_back', proposal.status
    assert_equal played.fetch('candidate').sort, proposal.evaluation.fetch('regression_case_ids').sort
    assert_equal 48, proposal.evaluation.dig('rollout', 'candidate_average_loss')
    assert_equal 24, Improvement.escalation_hours(NevaehOnboardingCase.find(played.fetch('candidate').first))
    16.times do
      entry = Assignment.start!(paid_trial(paid_at: 73.hours.ago))
      entry.update!(dashboard_at: entry.paid_at + 30.hours)
    end
    improvement.evaluate!
    next_proposal = NevaehOnboardingPlaybook.find_by(operator: @operator, status: 'proposed')
    if next_proposal
      refute_equal 48, next_proposal.escalate_after_hours
      assert_equal played.fetch('candidate').sort, next_proposal.evaluation.fetch('regression_case_ids').sort
    end
  end

  def test_mailbox_retry_budget_and_readiness
    trial = paid_trial(paid_at: 1.hour.ago)
    LightekAgency::TrialRequest.create!(site_id: trial.billing_site_id, operator_id: @operator.id,
      email_address: trial.prospect.email_address, confirmed_at: Time.current)
    Assignment.record_dashboard!(trial.prospect)
    entry = Assignment.start!(trial)

    failure = ->(*, **) { raise LightekEmailProvisioningService::Unavailable }
    LightekEmailProvisioningService.stub(:provision_for_paid_agency!, failure) do
      2.times { Assignment.advance!(entry) }
      assert_equal 1, entry.reload.mailbox_attempts
      assert_nil entry.escalated_at
      travel 16.minutes
      Assignment.advance!(entry)
      travel 16.minutes
      Assignment.advance!(entry)
      assert_equal 3, entry.reload.mailbox_attempts
      assert_equal 'mailbox_configuration', entry.blocker
      assert entry.escalated_at?
      refute entry.completed_at?
    end
  end

  def test_resolution_cycles_share_approval_and_regression_controls
    cycle = NevaehImprovement::Cycle.new(@operator, 'agency_onboarding')
    adapter = NevaehImprovement::Agency
    signals = {'waiting_for_dashboard' => true, 'purchase_email_matches' => true}
    12.times do |i|
      row = cycle.observe!(10_000 + i, signals)
      row.update!(measured_at: Time.current, outcome: {'verified' => false})
    end
    cycle.evaluate!
    candidate = NevaehResolutionPlaybook.find_by!(operator: @operator, status: 'proposed')
    assert_equal 6, candidate.evidence.fetch('holdout_ids').size
    assert_raises(ActiveRecord::RecordNotFound) do
      NevaehImprovement::Cycle.new(@operator, 'purchased_service').decide!(candidate.id, approve: true)
    end

    adapter.stub(:available_for?, true) { cycle.decide!(candidate.id, approve: true) }
    assert_equal 'trial', candidate.reload.status
    row = cycle.observe!(10_050, signals)
    row.update!(cohort: 'candidate', measured_at: Time.current, outcome: {'regression' => true})
    cycle.evaluate!
    assert_equal 'rolled_back', candidate.reload.status
    assert_equal [row.id], candidate.evidence.fetch('regression_ids')
    assert_equal 'baseline', cycle.strategy(row.reload)
    cycle.evaluate!
    refute NevaehResolutionPlaybook.where(operator: @operator, status: 'proposed').exists?
  end

  def test_mail_current_check_tracks_owner_arrival_and_payment
    cycle = NevaehImprovement::Cycle.new(@operator, 'agency_onboarding')
    trial = paid_trial(paid_at: 25.hours.ago)
    entry = Assignment.start!(trial)
    Assignment.advance!(entry)
    signals = {'waiting_for_dashboard' => true, 'purchase_email_matches' => true}
    row = cycle.observe!(entry.id, signals)
    playbook = NevaehResolutionPlaybook.create!(operator: @operator, workflow: 'agency_onboarding',
      status: 'trial', strategy: 'email_24h', evidence_digest: SecureRandom.hex)
    row.update!(cohort: 'candidate', playbook: playbook, receipt: {'message_id' => 5})
    mail = Struct.new(:id, :idempotency_key, :to_addresses, :account_id).new(5,
      "agency_onboarding_#{row.id}", [trial.prospect.email_address], 7)
    verified_sender = Struct.new(:id).new(7)

    NevaehImprovement::Agency.stub(:sender, verified_sender) do
      assert NevaehImprovement::Agency.current_message?(mail)
      Assignment.record_dashboard!(trial.prospect)
      refute NevaehImprovement::Agency.current_message?(mail)
      entry.reload.update!(dashboard_at: nil)
      trial.order.update!(status: 'refunded')
      refute NevaehImprovement::Agency.current_message?(mail)
    end
  end

  def test_purchased_service_pilot_requires_owned_visit_and_ignores_repeat_requests
    pilot = NevaehImprovement::PurchasedService
    first_trial = paid_trial
    second_trial = paid_trial
    playbook = NevaehResolutionPlaybook.create!(operator: @operator, workflow: pilot::KEY,
      status: 'active', strategy: 'direct_service_link', evidence_digest: SecureRandom.hex)
    fields = {'customer_service' => {'state' => 'answered', 'topic' => 'find_services'}}
    first = Marlon::Ticket.create!(submitted_by: first_trial.prospect, extra_fields: fields)
    duplicate = Marlon::Ticket.create!(submitted_by: first_trial.prospect, extra_fields: fields)
    reopened = Marlon::Ticket.create!(submitted_by: second_trial.prospect, extra_fields: fields)

    LightekPwa::Policy.stub(:platform_operator, @operator) do
      [first, duplicate, reopened].each { |ticket| pilot.start!(ticket) }
    end
    rows = NevaehResolutionObservation.where(playbook: playbook)
    assert_equal [first.id, reopened.id], rows.pluck(:subject_id).sort
    assert_equal 1, DymondDash::Notification.where(subject: first_trial.order).count
    receipt = rows.find_by!(subject_id: first.id)
    pilot.record_visit!(second_trial.prospect, first_trial.order)
    assert_nil receipt.reload.receipt['opened_at']
    pilot.record_visit!(first_trial.prospect, first_trial.order)
    assert receipt.reload.receipt['opened_at']
    pilot.record_visit!(second_trial.prospect, second_trial.order)
    reopened.events.create!(action: NevaehCustomerService::Cases::CUSTOMER_REPLY)
    travel 8.days
    rows.each { |row| pilot.measure!(row) }
    assert receipt.reload.outcome['verified']
    refute rows.find_by!(subject_id: reopened.id).outcome['verified']
    assert rows.find_by!(subject_id: reopened.id).outcome['reopened']
  end

  private

  def assert_difference_in_playbooks(difference)
    scope = NevaehOnboardingPlaybook.where(operator: @operator)
    count = scope.count
    yield
    assert_equal count + difference, scope.count
  end

  def paid_trial(paid_at: 1.hour.ago)
    prospect = User.create!(role: 'white_label', agency_id: @operator.id, email_address: "agency-#{SecureRandom.hex(5)}@example.com")
    order = LightekCommerce::Order.create!(status: 'fulfilled', purpose: 'agency_membership', paid_at: paid_at,
      site_id: 1, hosting_owner_id: prospect.id, customer_email: prospect.email_address)
    LightekAgency::Trial.create!(operator: @operator, prospect: prospect, order: order, billing_site_id: 1,
      activated_at: paid_at, paid_through: 1.year.from_now, created_at: paid_at - 1.hour).tap do |trial|
      order.update!(fulfillment_reference: "agency-trial-#{trial.id}")
    end
  end
end
