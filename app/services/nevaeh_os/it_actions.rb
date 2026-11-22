# frozen_string_literal: true

module NevaehOs
  module ItActions
    INPUTS = {
      'hosting.fleet.rollback' => {'target_id'=>:id, 'confirmed'=>:confirmation},
      'hosting.fleet.recovery.status' => {'target_id'=>:id},
      'hosting.fleet.backup.drill' => {'target_id'=>:id},
      'hosting.fleet.backup.status' => {'operation_id'=>:id},
      'hosting.project.dns.repair' => {'project_id'=>:id},
      'mail.mailbox.receiving.repair' => {'mailbox_id'=>:id},
      'support.ticket.confirm_resolution' => {'ticket_number'=>:ticket_number, 'confirmed'=>:confirmation},
      'support.ticket.reply' => {'ticket_number'=>:ticket_number, 'detail'=>:mail_body},
      'identity.lifecycle.review' => {'employer_id'=>:id, 'case_id'=>:id},
      'identity.directory.grant.review' => {'employer_id'=>:id, 'grant_id'=>:id},
      'identity.sso.containment.review' => {'employer_id'=>:id, 'membership_id'=>:id}
    }.transform_values(&:freeze).freeze

    module_function

    def authorize!(actor, intent, values)
      raise ArgumentError, 'An active account is required' unless actor&.persisted? && LightekPeople::LifecycleAccess.active?(actor)

      case intent
      when 'identity.lifecycle.review'
        employer = LightekPeople::Lifecycle.employers_for(actor).find(values.fetch('employer_id'))
        LightekPeople::Lifecycle.authorize_review!(actor: actor, employer: employer)
        LightekPeople::LifecycleCase.where(employer: employer).find(values.fetch('case_id'))
      when 'identity.directory.grant.review', 'identity.sso.containment.review'
        employer = LightekPeople::Access.employers_for(actor).find(values.fetch('employer_id'))
        LightekPeople::Access.new(actor: actor, employer: employer).require!(:directory)
        if intent == 'identity.directory.grant.review'
          LightekIdentity::ResourceGrant.where(employer: employer).find(values.fetch('grant_id'))
        else
          LightekPeople::Employment.where(employer: employer).find(values.fetch('membership_id'))
        end
      when 'support.ticket.confirm_resolution'
        Marlon::Ticket.where(submitted_by: actor).find_by!(number: values.fetch('ticket_number'))
      when 'support.ticket.reply'
        ticket = Marlon::Ticket.find_by!(number: values.fetch('ticket_number'))
        abilities = Ability.new(actor)
        unless abilities.can?(:read, ticket) && abilities.can?(:reply, ticket)
          raise ArgumentError, 'Support reply permission required'
        end
        ticket
      else
        raise ArgumentError, 'Gatekeeper operator access required' unless Gatekeeper::Hosting::Access.super_admin?(actor)

        case intent
        when 'hosting.project.dns.repair' then GatekeeperProject.find(values.fetch('project_id'))
        when 'mail.mailbox.receiving.repair' then LightekMail::Access.accounts(actor).find(values.fetch('mailbox_id'))
        when 'hosting.fleet.backup.status'
          GatekeeperOperation.where(capability: Gatekeeper::Fleet::BackupDrill::CAPABILITY).find(values.fetch('operation_id'))
        else GatekeeperUpdateTarget.find(values.fetch('target_id'))
        end
      end
    rescue LightekPeople::Access::Denied => error
      raise ArgumentError, error.message
    end

    def perform!(actor, intent, target, values)
      case intent
      when 'hosting.fleet.rollback'
        rollout = Gatekeeper::Fleet::Recovery.rollback!(target: target, actor: actor)
        {'rollout_id'=>rollout.id, 'status'=>rollout.status,
         'links'=>[{'label'=>'Follow rollback rollout', 'url'=>"/dashboard/infrastructure/updates/#{rollout.id}"}]}
      when 'hosting.fleet.recovery.status'
        Gatekeeper::Fleet::Recovery.receipt(target)
      when 'hosting.fleet.backup.drill'
        Gatekeeper::Fleet::BackupDrill.queue!(actor: actor, target: target)
      when 'hosting.fleet.backup.status'
        {'operation_id'=>target.id, 'status'=>target.status, 'restored_schema'=>target.result.to_h['restored_schema'] == true,
         'completed_at'=>target.completed_at&.iso8601}
      when 'hosting.project.dns.repair'
        target.with_lock { Gatekeeper::ManagedDnsRepair.project!(target) }
      when 'mail.mailbox.receiving.repair'
        target.domain.with_lock { Gatekeeper::ManagedDnsRepair.mailbox!(target.reload) }
      when 'support.ticket.confirm_resolution'
        target.confirm_customer_resolution!(actor: actor)
        {'ticket_id'=>target.id, 'status'=>target.status,
         'links'=>[{'label'=>'Open Support Center', 'url'=>'/supports'}]}
      when 'support.ticket.reply'
        event = target.reply_as_support!(actor: actor, detail: values.fetch('detail'))
        {'ticket_id'=>target.id, 'event_id'=>event.id, 'status'=>target.status}
      when 'identity.lifecycle.review'
        {'status'=>'review_required', 'case_id'=>target.id, 'text'=>'Open the case to verify your session and review its access changes.',
         'links'=>[{'label'=>'Review lifecycle case', 'url'=>"/dashboard/people/lifecycle?employer_id=#{target.employer_id}&case_id=#{target.id}"}]}
      when 'identity.directory.grant.review'
        {'status'=>'review_required', 'grant_id'=>target.id, 'text'=>'Open Directory to verify your session and review this grant for revocation.',
         'links'=>[{'label'=>'Review directory grant', 'url'=>"/dashboard/directory?employer_id=#{target.employer_id}#directory-grant-#{target.id}"}]}
      when 'identity.sso.containment.review'
        {'status'=>'review_required', 'membership_id'=>target.id, 'text'=>'Open Directory to verify your session and review revocation of existing company SSO sessions.',
         'links'=>[{'label'=>'Review session revocation', 'url'=>"/dashboard/directory?employer_id=#{target.employer_id}#directory-member-#{target.id}"}]}
      end
    rescue Gatekeeper::Fleet::Rollouts::Invalid, Gatekeeper::Hosting::Access::Denied, Gatekeeper::ManagedDnsRepair::Conflict => error
      raise ArgumentError, error.message
    end
  end
end
