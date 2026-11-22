# frozen_string_literal: true
module NevaehOs
  # Bounded operational reviews. Domain access services remain authoritative.
  module SpecialistTasks
    DEFINITIONS={
      'website'=>['Review open website audit findings','site_id'],
      'sales'=>['Find overdue sales follow-ups','site_id'],
      'customer_service'=>['Review unresolved customer cases',nil],
      'billing'=>['Review my overdue invoices and billing cases',nil],
      'finance'=>['Find uncategorized accounting transactions','employer_id'],
      'payroll'=>['Find payroll drafts due for approval','employer_id'],
      'commerce'=>['Find paid orders awaiting fulfillment','site_id'],
      'people'=>['Review unfinished onboarding and offboarding','employer_id'],
      'hosting'=>['Review saved server health',nil],
      'compliance'=>['Find stale or failed jurisdiction monitors','employer_id']
    }.freeze
    LIMIT=30
    module_function
    def topic(role)
      %w[customer_service billing].include?(role) ? role : 'specialist_tasks'
    end

    def capability(role) = "operations.#{role}.review"
    def example(role)
      input=DEFINITIONS.fetch(role)[1]
      "/operations #{role}"+(input ? " {\"#{input}\":1}" : '')
    end
    def authorize!(actor,command)
      raise ArgumentError,'Sign in first' unless actor&.persisted?
      role=command.fetch('role')
      definition=DEFINITIONS.fetch(role) { raise ArgumentError,'Choose a supported specialist review' }
      values=command.fetch('inputs',{})
      input=definition[1]
      raise ArgumentError,'Use only the named review input' unless values.is_a?(Hash) && (values.keys-[input].compact).empty?
      raise ArgumentError,"Choose a positive #{input}" if input && !values[input].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
      case role
      when 'customer_service'
        raise ArgumentError,'Active Lightek staff access required' unless actor.employee? && LightekPeople::LifecycleAccess.active?(actor)
        NevaehCustomerService::Cases.scope
      when 'billing'
        raise ArgumentError,'Active billing account required' unless LightekPeople::LifecycleAccess.active?(actor)
        actor
      when 'website'
        site=LightekSales::Access.sites_for(actor).find(values.fetch('site_id'))
        LightekGrowth::Audits::Access.new(actor:actor,site:site).read!
        site
      when 'sales'
        site=LightekSales::Access.sites_for(actor).find(values.fetch('site_id'))
        LightekSales::Workspace.new(actor:actor,site:site).revalidate!
        site
      when 'commerce'
        raise ArgumentError,'Commerce administration required' unless %w[super_admin admin white_label client].include?(actor.role)
        LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
      when 'hosting'
        Gatekeeper::Hosting::Access.nodes(actor)
      else
        employer=LightekPeople::Access.employers_for(actor).find(values.fetch('employer_id'))
        case role
        when 'finance' then LightekAccounting::Access.new(actor:actor,employer:employer).require!(:read)
        when 'compliance' then LightekCompliance::Access.authorize!(actor,employer)
        else LightekPeople::Access.new(actor:actor,employer:employer).require!(role=='people' ? :people : :read)
        end
        employer
      end
    rescue LightekPeople::Access::Denied,LightekAccounting::Access::Denied,Gatekeeper::Hosting::Access::Denied,LightekAgency::PackagePolicy::Denied => error
      raise ArgumentError,error.message
    end
    def summary(scope,fields)
      {'count'=>scope.count,'records'=>scope.reorder(id: :asc).limit(LIMIT).map { |row| row.attributes.slice(*fields) },'limit'=>LIMIT}
    end
    def perform!(actor:,command:)
      context=authorize!(actor,command) # Re-resolve domain access at execution, never trust a saved scope.
      role=command.fetch('role')
      data=case role
      when 'customer_service'
        summary(context.where(status: %w[open in_progress]), %w[id category assigned_team status created_at])
      when 'billing'
        overdue = NevaehCustomerService::Cases.invoices(context).where(status: "open")
          .where("amount_remaining_cents > 0 AND due_date < ?", Date.current)
        cases = NevaehCustomerService::Cases.customer_scope(context).where(category: "billing", status: %w[open in_progress])
        {'overdue_invoices'=>summary(overdue, %w[id number due_date status]),
         'open_cases'=>summary(cases, %w[id number status created_at])}
      when 'website'
        audits=LightekGrowth::WebsiteAudit.where(site:context)
        latest=audits.order(id: :desc).first
        latest ? summary(LightekGrowth::AuditFinding.where(site:context,website_audit:latest,status:'open'),%w[id severity status page_id rule]).merge('audit_id'=>latest.id,'audit_created_at'=>latest.created_at&.iso8601) : {'count'=>0,'records'=>[],'coverage'=>'No saved website audit; run an audit in Website audits first.'}
      when 'sales'
        workspace=LightekSales::Workspace.new(actor:actor,site:context)
        {'leads'=>summary(workspace.scope('lead').where(status:%w[new contacted qualified]).where('follow_up_on <= ?',Date.current),%w[id status follow_up_on]),
         'opportunities'=>summary(workspace.scope('opportunity').open_pipeline.where('follow_up_on <= ?',Date.current),%w[id stage follow_up_on])}
      when 'finance'
        access=LightekAccounting::Access.new(actor:actor,employer:context);access.require!(:read)
        summary(LightekAccounting::Transaction.where(book_id:access.books.select(:id),category_id:nil),%w[id book_id posted_on])
      when 'payroll'
        summary(LightekPeople::PayRun.where(employer:context,status:'draft').where('pay_date <= ?',Date.current),%w[id status period_start period_end pay_date])
      when 'commerce'
        summary(LightekCommerce::Order.visible.where(site:context,status:'paid'),%w[id status paid_at provisioned_at])
      when 'people'
        summary(LightekPeople::LifecycleCase.where(employer:context,status:%w[open access_revoked]),%w[id kind status created_at])
      when 'hosting'
        summary(context.where.not(status:%w[healthy decommissioned]),%w[id status updated_at]).merge('coverage'=>'Saved node status only; no live health probe or automatic remediation.')
      when 'compliance'
        scope=LightekCompliance::Monitor.where(employer:context,enabled:true)
        due=scope.where('last_checked_at IS NULL OR last_checked_at < ? OR error_code IS NOT NULL',24.hours.ago)
        summary(due,%w[id state provider last_checked_at error_code]).merge('review_required'=>true,'coverage'=>'Source freshness only; findings require legal review.')
      end
      {'status'=>'completed','success'=>true,'task'=>capability(role),'checked_at'=>Time.current.iso8601,
       'context'=>command.fetch('inputs',{}),'result'=>data,'summary'=>DEFINITIONS.fetch(role)[0],
       'completion_basis'=>'Review of authorized saved records; flagged work remains pending owner action. No records were changed.'}
    end
  end
end
