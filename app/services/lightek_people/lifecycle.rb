# frozen_string_literal: true
module LightekPeople
  class Lifecycle
    STEPS = {
      'employee_onboarding' => {'identity' => ['people', 'Confirm identity, role, start date and employment documents'], 'equipment' => ['directory', 'Prepare equipment and review least-privilege access'], 'orientation' => ['people', 'Complete orientation, policies and training']},
      'employee_offboarding' => {'handoff' => ['people', 'Confirm manager, open-work and knowledge handoff'], 'equipment' => ['directory', 'Confirm equipment return, directory sync and external SSH/VPN/device access revocation'], 'records' => ['people', 'Review final payroll/benefits and records retention']},
      'agency_onboarding' => {'business' => ['owner', 'Verify agency identity, terms and billing arrangements'], 'brand' => ['owner', 'Review branding, packages and client support ownership'], 'access' => ['owner', 'Confirm MFA, Connect access and client-management responsibilities']},
      'agency_offboarding' => {'clients' => ['owner', 'Confirm ongoing client service ownership and upstream continuity'], 'access' => ['owner', 'Verify external integration and client-instance credential revocation'], 'billing' => ['owner', 'Review remaining subscriptions, payouts and retained business records']}
    }.freeze
    def initialize(actor:, employer:)
      @actor, @employer = actor, employer
      raise Access::Denied, 'Account access suspended' unless LifecycleAccess.active?(actor)
      @access = Access.new(actor: actor, employer: employer) unless actor.role == 'super_admin'
    end
    def start!(kind:, subject:)
      raise ArgumentError, 'Choose a supported lifecycle.' unless STEPS.key?(kind)
      authorize!(kind.start_with?('agency_') ? :owner : :people)
      @employer.with_lock do
        authorize!(kind.start_with?('agency_') ? :owner : :people)
        record = LifecycleCase.where(employer: @employer, subject: subject).where.not(status: %w[completed canceled]).first
        if record
          raise ArgumentError, 'Close the current lifecycle before preparing another.' unless record.kind == kind
          return record
        end
        if kind == 'employee_onboarding' && subject.active?
          raise ArgumentError, 'Prepare an inactive team membership before onboarding.'
        end
        record = LifecycleCase.create!(employer: @employer, subject: subject, kind: kind, created_by: @actor)
        emit('prepared', record)
        record
      end
    end
    def attest!(id:, step:, evidence:, version:)
      record = find(id)
      record.with_lock do
        version!(record, version)
        raise ArgumentError, 'This lifecycle is complete.' if record.status.in?(%w[completed canceled])
        permission, = STEPS.fetch(record.kind).fetch(step) { raise ArgumentError, 'Choose an installed checklist step.' }
        authorize!(permission.to_sym)
        raise ArgumentError, 'Record the completed work or evidence (up to 2000 characters).' if evidence.to_s.strip.blank? || evidence.to_s.length > 2000
        record.update!(steps: record.steps.merge(step => {'actor_id' => @actor.id, 'at' => Time.current.iso8601, 'evidence' => evidence.to_s.strip}))
      end
      record
    end
    def revoke!(id:, version:)
      record = find(id)
      raise ArgumentError, 'Choose an offboarding case.' unless record.kind.end_with?('_offboarding')
      authorize!(record.kind == 'agency_offboarding' ? :owner : :directory)
      @employer.with_lock do
        record.reload
        authorize!(record.kind == 'agency_offboarding' ? :owner : :directory)
        next if record.access_revoked_at?
        version!(record, version)
        user = record.subject.is_a?(Employment) ? record.subject.worker : record.subject
        raise ArgumentError, 'An owner cannot offboard their own account through this workflow.' if user.id == @employer.id || user.role == 'super_admin'
        sites = DymondSite::Site.where(tenant_type: 'User', tenant_id: account_tree(record.subject.is_a?(Employment) ? @employer : user))
        receipt = {'site_ids' => sites.pluck(:id), 'handoff_user_ids' => [user.id], 'handoff_state' => 'pending'}
        if record.subject.is_a?(Employment)
          member = record.subject
          end_date = member.starts_on <= Date.current ? [member.ends_on || Date.current, Date.current].min : member.ends_on
          member.lifecycle_revocation = true
          member.update!(active: false, ends_on: end_date, people_admin: false, directory_admin: false, payroll_access: 'none', accounting_access: 'none', compliance_access: 'none')
          grants = LightekIdentity::ResourceGrant.where(employer_id: @employer.id, subject: member)
          receipt['resource_grants_revoked'] = grants.count
          grants.find_each(&:destroy!)
          receipt['site_memberships_revoked'] = LightekAgency::SiteMembership.where(site_id: sites.select(:id), user: user).delete_all
          # Business-role accounts and memberships at other employers remain usable.
          if user.role.in?(%w[employee contractor]) && !Employment.active.where(worker: user).exists?
            user.update!(access_suspended_at: Time.current, access_suspension_source: 'employment')
          end
        else
          user.update!(access_suspended_at: Time.current, access_suspension_source: 'agency')
          receipt['client_accounts_preserved'] = user.agency_clients.count
          own_sites = DymondSite::Site.where(tenant_type: 'User', tenant_id: user.id)
          receipt['own_site_intake_rules_disabled'] = LightekSales::IntakeRule.where(site_id: own_sites.select(:id), enabled: true).update_all(enabled: false)
          staff = Employment.where(employer: user)
          receipt['team_memberships_revoked'] = staff.count
          receipt['team_sessions_revoked'] = 0
          staff.includes(:worker).find_each do |member|
            worker = member.worker
            member.lifecycle_revocation = true
            end_date = member.starts_on <= Date.current ? [member.ends_on || Date.current, Date.current].min : member.ends_on
            member.update!(active: false, ends_on: end_date, people_admin: false, directory_admin: false, payroll_access: 'none', accounting_access: 'none', compliance_access: 'none')
            LightekIdentity::ResourceGrant.where(employer_id: user.id, subject: member).find_each(&:destroy!)
            LightekAgency::SiteMembership.where(site_id: sites.select(:id), user: worker).delete_all
            unless worker.role == 'super_admin' || worker.id == user.id
              receipt['team_sessions_revoked'] += worker.sessions.delete_all
              worker.regenerate_api_token
              if worker.role.in?(%w[employee contractor]) && !Employment.active.where(worker: worker).exists?
                worker.update!(access_suspended_at: Time.current, access_suspension_source: 'employment')
              end
            end
            receipt['handoff_user_ids'] << worker.id
          end
        end
        LightekAgency::SiteMembership.where(site_id: sites.select(:id), user: user).delete_all
        receipt['sessions_revoked'] = user.sessions.delete_all
        user.regenerate_api_token
        connections = record.kind == 'agency_offboarding' ? LightekConnect::Connection.where(user: user, revoked_at: nil) : LightekConnect::Connection.none
        receipt['connect_connections_revoked'] = connections.count
        connections.find_each(&:revoke!)
        record.update!(status: 'access_revoked', access_revoked_at: Time.current, revoked_by: @actor, receipt: receipt)
      end
      emit('access_revoked', record)
      recover_handoff!(record)
      record
    end
    def complete!(id:, version:)
      record = find(id)
      @employer.with_lock do
        record.reload
        if record.kind == 'employee_onboarding'
          authorize!(:directory)
          member = record.subject
          authorize!(:owner) if member.directory_admin? || member.people_admin? || [member.payroll_access, member.accounting_access, member.compliance_access].any? { |value| value != 'none' }
        else
          authorize!(record.kind == 'employee_offboarding' ? :people : :owner)
        end
        return record if record.status == 'completed'
        raise ArgumentError, 'Canceled onboarding cannot be activated.' if record.status == 'canceled'
        version!(record, version)
        raise ArgumentError, 'Complete every checklist step first.' unless (STEPS.fetch(record.kind).keys - record.steps.keys).empty?
        if record.kind.end_with?('_offboarding')
          raise ArgumentError, 'Revoke access before completing offboarding.' unless record.access_revoked_at?
          raise ArgumentError, 'Finish or retry the open-work handoff before completing offboarding.' unless record.receipt['handoff_state'] == 'completed'
        elsif record.subject.is_a?(Employment)
          member = record.subject
          raise ArgumentError, 'Activate within the employee start/end dates.' if member.starts_on > Date.current || (member.ends_on && member.ends_on < Date.current)
          member.lifecycle_activation = true
          member.update!(active: true)
          user = member.worker
          user.update!(access_suspended_at: nil, access_suspension_source: nil) if user.access_suspension_source == 'employment'
        else
          agency = record.subject
          raise ArgumentError, 'This account needs a separate security review.' unless LifecycleAccess.active?(agency) || agency.access_suspension_source == 'agency'
          agency.update!(access_suspended_at: nil, access_suspension_source: nil) if agency.access_suspension_source == 'agency'
        end
        record.update!(status: 'completed', completed_at: Time.current, completed_by: @actor)
        emit('completed', record)
      end
      record
    end
    def cancel!(id:, version:)
      record = find(id)
      authorize!(record.kind == 'employee_onboarding' ? :people : :owner)
      record.with_lock do
        version!(record, version)
        raise ArgumentError, 'Only open onboarding can be canceled.' unless record.kind.end_with?('_onboarding') && record.status == 'open'
        record.update!(status: 'canceled', completed_by: @actor, completed_at: Time.current)
        emit('onboarding_canceled', record)
      end
      record
    end
    private
    def recover_handoff!(record)
      @employer.with_lock do
        record.reload
        return if record.receipt['handoff_state'] == 'completed'
        sites = DymondSite::Site.where(id: record.receipt.fetch('site_ids'))
        counts = record.receipt.fetch('handoff_user_ids').uniq.to_h { |id| [id.to_s, handoff(User.find(id), sites)] }
        record.update!(receipt: record.receipt.merge('handoff_state' => 'completed', 'handoff_actor_id' => @actor.id, 'handoff_at' => Time.current.iso8601, 'sales_handoff' => counts, 'handoff_error' => nil, 'handoff_failed_record' => nil))
        emit('handoff_completed', record)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError, ArgumentError => error
      # Business-data repair must not roll back a committed security revocation.
      record.reload.with_lock do
        record.update!(receipt: record.receipt.merge('handoff_state' => 'needs_attention', 'handoff_actor_id' => @actor.id, 'handoff_at' => Time.current.iso8601, 'handoff_error' => error.message.first(300), 'handoff_failed_record' => (error.respond_to?(:record) ? {'type' => error.record.class.name, 'id' => error.record.id, 'site_id' => (error.record.site_id if error.record.respond_to?(:site_id))} : nil)))
        emit('handoff_needs_attention', record)
      end
    end
    def emit(event, record)
      Rails.logger.info({event: "lightek.lifecycle.#{event}", lifecycle_case_id: record.id, employer_id: @employer.id, actor_id: @actor.id, status: record.status, handoff_state: record.receipt['handoff_state']}.to_json)
    end
    def authorize!(permission)
      @actor.reload
      raise Access::Denied, 'Account access suspended' unless LifecycleAccess.active?(@actor)
      return if @actor.role == 'super_admin'
      @access ||= Access.new(actor: @actor, employer: @employer)
      @access.require!(permission)
    end
    def find(id) = LifecycleCase.where(employer: @employer).find(id)
    def version!(record, version)
      raise ActiveRecord::StaleObjectError.new(record, 'update') unless version.to_s.match?(/\A\d+\z/) && record.lock_version == version.to_i
    end
    def account_tree(root)
      ids, frontier = [root.id], [root.id]
      while frontier.any?
        frontier = User.where(agency_id: frontier).where.not(id: ids).pluck(:id)
        ids.concat(frontier)
      end
      ids
    end
    def handoff(user, sites)
      counts = Hash.new(0)
      sites.find_each do |site|
        recipient = site.tenant_id == user.id ? @employer : site.tenant
        next unless recipient.is_a?(User)
        unless LightekSales::Access.owners_for(site).exists?(id: recipient.id)
          LightekAgency::SiteMembership.find_or_create_by!(site: site, user: recipient) { |member| member.role = 'manager'; member.granted_by = @actor }
        end
        [['LightekSales::Lead', 'owner_id'], ['LightekSales::Opportunity', 'owner_id'], ['LightekSales::Account', 'owner_id'], ['LightekMarketing::Contact', 'sales_owner_id'], ['LightekSales::RoutingRule', 'owner_id'], ['LightekSales::Task', 'owner_id']].each do |name, key|
          rows = name.constantize.where(site: site, key => user.id)
          rows = rows.active if name == 'LightekSales::Lead'
          rows = rows.open_pipeline if name == 'LightekSales::Opportunity'
          rows = rows.where(status: 'open') if name == 'LightekSales::Task'
          counts[name] += rows.count
          rows.find_each do |row|
            row.update!(key => recipient.id)
            target = name == 'LightekSales::Task' ? row.record : row
            LightekSales::Activity.create!(site: site, actor: @actor, record: target, kind: 'note', body: "Offboarding handoff: reassigned from user ##{user.id} to business owner ##{recipient.id}.")
          end
        end
      end
      counts
    end
  end
end
