# Real SQLite records, OS dispatch, domain employer/hosting policies and journal.
# External site-membership/package services are controlled account-boundary fixtures.
require_relative 'nevaeh_os_test'
ActiveRecord::Schema.define do
  create_table(:test_website_pages) { |t| t.integer :site_id,:position; t.string :title,:slug; t.boolean :published }
  add_column :test_sites,:tenant_id,:integer
  add_column :test_sites,:tenant_type,:string
  create_table(:lightek_people_employments) { |t| t.integer :employer_id,:worker_id; t.boolean :active; t.date :starts_on,:ends_on; t.string :payroll_access,:accounting_access,:compliance_access; t.boolean :people_admin,:directory_admin; t.string :level }
  create_table(:lightek_people_pay_runs) { |t| t.integer :employer_id; t.string :status; t.date :pay_date,:period_start,:period_end }
  create_table(:lightek_people_lifecycle_cases) { |t| t.integer :employer_id; t.string :kind,:status; t.timestamps }
  create_table(:lightek_compliance_monitors) { |t| t.integer :employer_id; t.boolean :enabled; t.string :state,:provider,:error_code; t.datetime :last_checked_at }
  create_table(:lightek_accounting_books) { |t| t.integer :employer_id }
  create_table(:lightek_accounting_transactions) { |t| t.integer :book_id,:category_id; t.date :posted_on; t.string :record_key,:sealed_data }
  create_table(:lightek_sales_leads) { |t| t.integer :site_id; t.string :status; t.date :follow_up_on }
  create_table(:lightek_sales_opportunities) { |t| t.integer :site_id; t.string :stage; t.date :follow_up_on }
  create_table(:lightek_commerce_orders) { |t| t.integer :site_id; t.string :status; t.datetime :paid_at,:provisioned_at,:deleted_at }
  create_table(:lightek_growth_website_audits) { |t| t.integer :site_id; t.timestamps }
  create_table(:lightek_growth_audit_findings) { |t| t.integer :site_id,:website_audit_id,:page_id; t.string :severity,:status,:rule }
  create_table(:gatekeeper_nodes) { |t| t.integer :owner_id; t.string :owner_type,:status; t.timestamps }
end
class DymondSite::Site
  belongs_to :tenant,polymorphic:true
  has_many :pages,class_name:'DymondSite::Page',foreign_key: :site_id
end
class DymondSite::Page < ApplicationRecord
  self.table_name='test_website_pages'
end
require File.join(ROOT,'app/services/nevaeh_intelligences/structured_actions')
require File.join(ROOT,'app/models/concerns/sales_site_record')
require File.join(ROOT,'app/models/concerns/accounting_sealed_record')
%w[lightek_people/employment lightek_people/pay_run lightek_people/lifecycle_case lightek_compliance/monitor lightek_accounting/book lightek_accounting/transaction lightek_sales/lead lightek_sales/opportunity lightek_commerce/order lightek_growth/website_audit lightek_growth/audit_finding gatekeeper_node].each { |file| require File.join(ROOT,'app/models',file) }
%w[lightek_people/access lightek_accounting/access lightek_compliance/access gatekeeper/hosting/access].each { |file| require File.join(ROOT,'app/services',file) }
module LightekAgency
  module PackagePolicy
    class Denied < StandardError; end
    def self.authorize!(_account,_feature) = true
  end
end
module LightekSales
  # Fixture for the host engine's account/site membership boundary.
  module Access
    def self.sites_for(actor) = DymondSite::Site.where(tenant_id:actor.id,tenant_type:'User')
  end
  class Workspace
    def initialize(actor:,site:)
      @actor,@site=actor,Access.sites_for(actor).find(site.id)
    end
    def revalidate! = Access.sites_for(@actor.reload).find(@site.id)
    def scope(kind) = (kind=='lead' ? Lead : Opportunity).where(site_id:@site.id)
  end
end
module LightekSettings
  module WebsiteIdentity
    def self.sites_for(actor) = LightekSales::Access.sites_for(actor)
  end
end
module LightekGrowth
  module Audits
    class Access
      def initialize(actor:,site:)
        @actor,@site=actor,site
      end
      def read! = LightekSales::Access.sites_for(@actor).find(@site.id)
    end
  end
end
require File.join(ROOT,'app/services/lightek_marketing/campaign_producer')
# Only the campaign account entitlement/Studio access boundary is substituted;
# tests verify routing/authorization, not video rendering in this harness.
module LightekGrowth
  class Workspace
    def initialize(actor:,site:)
      @actor,@site=actor,site
    end
    def revalidate! = LightekSales::Access.sites_for(@actor).find(@site.id)
  end
end
module Studio
  module Broadcasting
    module Access
      def self.authorize!(actor,site) = LightekSales::Access.sites_for(actor).find(site.id)
    end
  end
end
require File.join(ROOT,'db/migrate/20261116040002_connect_nevaeh_specialist_reviews')
class NevaehSpecialistTasksChecks < NevaehOsTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  MODELS=[DymondSite::Page,LightekPeople::Employment,LightekPeople::PayRun,LightekPeople::LifecycleCase,LightekCompliance::Monitor,LightekAccounting::Transaction,LightekAccounting::Book,LightekSales::Lead,LightekSales::Opportunity,LightekCommerce::Order,LightekGrowth::AuditFinding,LightekGrowth::WebsiteAudit,GatekeeperNode,DymondSite::Site]
  def setup
    MODELS.each(&:delete_all)
    super
    @actor.update!(role:'client');@other.update!(role:'client')
    @site=DymondSite::Site.create!(host:'owned.test',tenant_id:@actor.id,tenant_type:'User')
    @foreign=DymondSite::Site.create!(host:'other.test',tenant_id:@other.id,tenant_type:'User')
    NevaehOs::Workforce.install!(@actor)
  end
  def insert(model,values)
    model.insert_all!([values]);model.order(:id).last
  end
  def task(role,foreign:false)
    input=NevaehOs::SpecialistTasks::DEFINITIONS.fetch(role)[1]
    id=input=='site_id' ? (foreign ? @foreign.id : @site.id) : (foreign ? @other.id : @actor.id)
    {'kind'=>'specialist_review','role'=>role,'inputs'=>input ? {input=>id} : {}}
  end
  def test_all_eight_reviews_execute_through_dispatch_and_persist_resolvable_reports
    insert(LightekSales::Lead,site_id:@site.id,status:'new',follow_up_on:Date.yesterday)
    insert(LightekSales::Lead,site_id:@foreign.id,status:'new',follow_up_on:Date.yesterday)
    insert(LightekSales::Opportunity,site_id:@site.id,stage:'qualified',follow_up_on:Date.current)
    book=insert(LightekAccounting::Book,employer_id:@actor.id)
    foreign_book=insert(LightekAccounting::Book,employer_id:@other.id)
    insert(LightekAccounting::Transaction,book_id:book.id,posted_on:Date.current)
    insert(LightekAccounting::Transaction,book_id:foreign_book.id,posted_on:Date.current)
    insert(LightekPeople::PayRun,employer_id:@actor.id,status:'draft',pay_date:Date.current)
    insert(LightekPeople::PayRun,employer_id:@other.id,status:'draft',pay_date:Date.current)
    insert(LightekPeople::LifecycleCase,employer_id:@actor.id,status:'open',kind:'employee_onboarding')
    insert(LightekPeople::LifecycleCase,employer_id:@other.id,status:'open',kind:'employee_onboarding')
    insert(LightekCommerce::Order,site_id:@site.id,status:'paid')
    insert(LightekCommerce::Order,site_id:@foreign.id,status:'paid')
    insert(GatekeeperNode,owner_type:'User',owner_id:@actor.id,status:'degraded')
    insert(GatekeeperNode,owner_type:'User',owner_id:@other.id,status:'degraded')
    insert(LightekCompliance::Monitor,employer_id:@actor.id,enabled:true,state:'NY',provider:'ny_openleg')
    insert(LightekCompliance::Monitor,employer_id:@other.id,enabled:true,state:'NY',provider:'ny_openleg')
    audit=insert(LightekGrowth::WebsiteAudit,site_id:@site.id)
    insert(LightekGrowth::AuditFinding,site_id:@site.id,website_audit_id:audit.id,status:'open',severity:'high')
    %w[website sales finance payroll commerce people hosting compliance].each do |role|
      receipt=NevaehOs::AgentWorkforce.create!(actor:@actor,command:{'agent_ref'=>role,'command'=>task(role)},key:SecureRandom.uuid)
      run=NevaehAgentRun.find(receipt.fetch('agent_run_id'))
      NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
      assert_equal 'completed',run.nevaeh_os_action.reload.status,role
      result=run.nevaeh_os_action.result.fetch('result')
      assert_equal 1,(role=='sales' ? result.fetch('leads') : result).fetch('count'),role
      report=NevaehOs::WorkerReports.capture!(run)
      structured=NevaehOs::WorkerReports.row(report).fetch(:structured_report)
      assert_equal run.task_uuid,structured['task_id']
      assert_equal 'completed',report.status
      assert NevaehOs::ReportJournal.read!(@actor).key?(run.task_uuid)
    end
  end
  def test_scheduled_review_and_goal_use_existing_worker_lifecycle
    receipt=NevaehOs::AgentWorkforce.create!(actor:@actor,command:{'agent_ref'=>'payroll','interval_minutes'=>5,'command'=>task('payroll')},key:SecureRandom.uuid)
    worker=NevaehAgentWorker.find(receipt['agent_worker_id'])
    assert_equal 'scheduled',receipt['status'];assert_equal 0,worker.runs.count
    worker.update!(next_run_at:1.minute.ago)
    NevaehOs::AgentWorkforce.tick!
    assert_equal 1,worker.runs.count
    run=worker.runs.first;NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
    assert_equal 'completed',run.nevaeh_os_action.reload.status
    worker.reload.update!(enabled:false);NevaehOs::AgentWorkforce.tick!;assert_equal 1,worker.runs.count
    plan=NevaehOs::Goals.create!(actor:@actor,values:{'title'=>'Check payroll queue','steps'=>[{'agent'=>'payroll','key'=>'review','command'=>task('payroll')}]},request_key:SecureRandom.uuid)
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start');NevaehOs::Goals.tick!(plan)
    assert_equal 'running',plan.steps.first.status
  end
  def test_reviews_exclude_current_completed_and_disabled_records
    insert(LightekPeople::PayRun,employer_id:@actor.id,status:'approved',pay_date:Date.yesterday)
    insert(LightekPeople::PayRun,employer_id:@actor.id,status:'draft',pay_date:Date.tomorrow)
    insert(LightekCompliance::Monitor,employer_id:@actor.id,enabled:false,state:'NY')
    insert(LightekCompliance::Monitor,employer_id:@actor.id,enabled:true,state:'NY',last_checked_at:Time.current)
    insert(LightekPeople::LifecycleCase,employer_id:@actor.id,status:'completed',kind:'employee_onboarding')
    insert(GatekeeperNode,owner_type:'User',owner_id:@actor.id,status:'healthy')
    insert(LightekCommerce::Order,site_id:@site.id,status:'fulfilled')
    %w[payroll compliance people hosting commerce].each do |role|
      result=NevaehOs::SpecialistTasks.perform!(actor:@actor,command:task(role))
      assert_equal 0,result.dig('result','count'),role
    end
  end
  def test_foreign_contexts_bad_inputs_and_wrong_specialists_are_blocked
    NevaehOs::SpecialistTasks::DEFINITIONS.each do |role, (_, input)|
      next unless input
      assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::SpecialistTasks.authorize!(@actor,task(role,foreign:true)) }
    end
    assert_raises(ArgumentError) { NevaehOs::SpecialistTasks.authorize!(@actor,task('hosting').merge('inputs'=>{'command'=>'rm'})) }
    assert_raises(ArgumentError) { NevaehOs::SpecialistTasks.authorize!(@actor,task('payroll').merge('inputs'=>{'employer_id'=>'1 OR 1=1'})) }
    assert_raises(ArgumentError) { NevaehOs::AgentWorkforce.create!(actor:@actor,command:{'agent_ref'=>'sales','command'=>task('payroll')},key:SecureRandom.uuid) }
    assert_equal 0,NevaehAgentRun.count
  end
  def test_permission_revocation_after_queue_blocks_execution
    receipt=NevaehOs::AgentWorkforce.create!(actor:@actor,command:{'agent_ref'=>'payroll','command'=>task('payroll')},key:SecureRandom.uuid)
    @actor.update!(role:'employee')
    run=NevaehAgentRun.find(receipt['agent_run_id']);NevaehOs::AgentWorkforce.execute!(run)
    assert_equal 'blocked',run.reload.status
    assert_nil run.nevaeh_os_action_id
  end
  def test_default_scope_upgrade_preserves_custom_restrictions_and_deleted_roles
    agent=NevaehOsAgent.find_by!(user:@actor,system_key:'payroll')
    agent.update!(allowed_capabilities:NevaehOs::Workforce::LEGACY_REVIEW_SCOPES.fetch('payroll'))
    custom=NevaehOsAgent.find_by!(user:@actor,system_key:'finance');custom.update!(allowed_capabilities:['susu.list'])
    ConnectNevaehSpecialistReviews.new.migrate(:up)
    assert_includes agent.reload.allowed_capabilities,'operations.payroll.review'
    assert_equal ['susu.list'],custom.reload.allowed_capabilities
    agent.update!(allowed_capabilities:NevaehOs::Workforce::LEGACY_REVIEW_SCOPES.fetch('payroll'))
    NevaehOs::Workforce.install!(@actor)
    refute_includes agent.reload.allowed_capabilities,'operations.payroll.review'
    row=NevaehOs::Workforce.rows(@actor).find { |r| r[:id]==custom.id }
    refute row[:examples].any? { |example| example.start_with?('/operations ') }
    refute row[:capabilities].any? { |cap| cap[:key]=='operations.finance.review' }
  end
  def test_bounds_empty_coverage_and_no_business_mutation
    report=NevaehOs::SpecialistTasks.perform!(actor:@actor,command:task('website'))
    assert_includes report.dig('result','coverage'),'No saved website audit'
    35.times { insert(LightekCommerce::Order,site_id:@site.id,status:'paid') }
    result=NevaehOs::SpecialistTasks.perform!(actor:@actor,command:task('commerce'))
    assert_equal 35,result.dig('result','count');assert_equal 30,result.dig('result','records').size
    assert_equal ['paid'],LightekCommerce::Order.distinct.pluck(:status)
    assert_equal ['id','paid_at','provisioned_at','status'],result.dig('result','records').first.keys.sort
  end
  def test_campaign_phrase_routes_from_sage_without_widening_sage_permissions
    result=NevaehOs::Conversation.new(actor:@actor,host:@site.host).ask(text:'make me a funny tiktok campaign ad promoting Lightek & services',agent:'sage',request_key:SecureRandom.uuid)
    assert_equal 'Campaign Producer',result['delegated_to']
    action=NevaehOsAction.find(result['action_id'])
    assert_equal 'agent_task',action.command['kind']
    campaign=NevaehOsAgent.find_by!(user:@actor,system_key:'campaign')
    assert_equal campaign.id.to_s,action.command['agent_ref']
    execute(action)
    run=NevaehAgentRun.find(action.reload.result['agent_run_id'])
    assert_equal campaign.id,run.snapshot['agent_id']
    assert_equal 'Lightek & services',run.snapshot.dig('values','service')
    sage=NevaehOsAgent.find_by!(user:@actor,system_key:'sage')
    assert_raises(ArgumentError) { NevaehOs::Agents.authorize!(run.snapshot.merge('agent_id'=>sage.id),@actor) }
    assert_equal ['growth.plan','growth.review'],sage.allowed_capabilities
  end
  def test_website_page_phrase_creates_verified_draft_and_returns_management_link
    result=NevaehOs::Conversation.new(actor:@actor,host:@site.host).ask(text:'Create a website page called running_from_nevaeh_screen',agent:'sage',request_key:SecureRandom.uuid)
    assert_equal 'Website Operator',result['delegated_to']
    outer=NevaehOsAction.find(result['action_id']);execute(outer)
    run=NevaehAgentRun.find(outer.reload.result['agent_run_id']);NevaehOs::AgentWorkforce.execute!(run)
    action=run.reload.nevaeh_os_action;execute(action)
    page=@site.pages.sole
    assert_equal 'running_from_nevaeh_screen',page.title
    assert_equal 'running-from-nevaeh-screen',page.slug
    refute page.published?
    assert_equal page.id,action.reload.result['page_id']
    assert_equal "/dashboard/pages?site_id=#{@site.id}",action.result.dig('links',0,'url')
    assert_equal 'completed',action.status
    execute(action);assert_equal 1,@site.pages.count
    report=NevaehOs::WorkerReports.capture!(run)
    assert_equal 'completed',report.status
    assert NevaehOs::ReportJournal.read!(@actor).key?(run.task_uuid)
    duplicate={'kind'=>'website_page','site_id'=>@site.id,'values'=>{'title'=>page.title}}
    assert_raises(ArgumentError) { NevaehOs::WebsitePages.create!(actor:@actor,command:duplicate) }
    assert_equal 1,@site.pages.count
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::WebsitePages.authorize!(@actor,duplicate.merge('site_id'=>@foreign.id)) }
  end
  def test_website_selection_requires_an_unambiguous_authorized_target
    second=DymondSite::Site.create!(host:'another.test',tenant_id:@actor.id,tenant_type:'User')
    error=assert_raises(ArgumentError) { NevaehOs::Conversation.new(actor:@actor).ask(text:'/website page {"title":"Test"}',request_key:SecureRandom.uuid) }
    assert_includes error.message,"##{second.id}"
    assert_equal 0,DymondSite::Page.count
    assert_equal 0,NevaehAgentRun.count
  end
  def test_review_templates_discovery_and_employer_report_scope
    assert_equal 'guide',command('/operations')['kind']
    assert_equal task('hosting'),command('/operations hosting')
    result=NevaehOs::Conversation.new(actor:@actor).ask(text:"/operations payroll {\"employer_id\":#{@actor.id}}",request_key:SecureRandom.uuid)
    assert_equal 'Payroll Coordinator',result['delegated_to']
    assert_equal "employer:#{@actor.id}",NevaehOs::WorkerReports.site_key(task('payroll'))
    refute_equal NevaehOs::WorkerReports.site_key(task('payroll')),NevaehOs::WorkerReports.site_key(task('payroll',foreign:true))
  end
end
