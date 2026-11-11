# frozen_string_literal: true
module NevaehOs
  module WatchReaction
    module_function
    def process!(event,apply:false)
      event.with_lock do
        return event if %w[dispatched blocked ignored].include?(event.status)
        return event if event.status=='prepared' && !apply
        watcher=event.nevaeh_watcher.reload
        actor=WatchEngine.authorize!(watcher)
        raise ArgumentError,'Watcher definition changed; this event requires a new baseline' unless event.plan['definition_fingerprint']==WatchContract.fingerprint(watcher)
        if watcher.response=='prepare' && (!apply || event.status!='prepared')
          plan=prepare(event)
          event.update!(status:'prepared',plan:event.plan.merge(plan),error:nil)
          return event
        end
        command=if watcher.response=='prepare'
          event.plan.fetch('command')
        elsif watcher.response=='update'
          {'kind'=>'ubuntu','operation'=>'setup','package'=>event.after_value.fetch('package')}
        else
          WatchContract.expand(watcher.command_template,variables(event))
        end
        command=command.merge('agent_id'=>watcher.nevaeh_os_agent_id)
        Executor.authorize_command!(actor:actor,command:command)
        worker=NevaehAgentWorker.create!(user:actor,nevaeh_os_agent:watcher.nevaeh_os_agent,name:"#{watcher.name}: #{event.entity}"[0,160],command:command)
        run=AgentWorkforce.request!(worker:worker,actor:actor,key:"watch-event-#{event.id}")
        event.update!(status:'dispatched',nevaeh_agent_run:run,error:nil,plan:event.plan.merge('command'=>command))
        AgentRunJob.perform_later(run.id)
        event
      end
    rescue ArgumentError,KeyError,ActiveRecord::RecordNotFound,Gatekeeper::AuthorizationDenied,LightekPwa::Policy::Denied => error
      event.with_lock { event.update!(status:'blocked',error:error.message[0,1000]) }
      event
    end
    def variables(event)
      value=event.after_value
      {'@event.package'=>value['package'],'@event.repository'=>value['repository'],'@event.branch'=>value['branch'],'@event.version'=>value['version'],'@event.entity'=>event.entity,'@event.source'=>value['source'] || value['uri']}
    end
    def prepare(event)
      value=event.after_value
      if value['package']
        watcher=event.nevaeh_watcher
        Executor.authorize_command!(actor:watcher.user.reload,command:{'kind'=>'ubuntu','operation'=>'plan','agent_id'=>watcher.nevaeh_os_agent_id})
        plan=UbuntuPackages.call(operation:'plan',package:value.fetch('package'))
        {'purpose'=>'Prepare Ubuntu installation','observation'=>value,'installation'=>plan,
         'command'=>{'kind'=>'ubuntu','operation'=>'setup','package'=>value.fetch('package')},
         'next_step'=>"Review this plan, then /watch apply #{event.id} to install and prepare the application adapter."}
      else
        description="Prepare installation for #{event.entity}. Source: #{value.to_json}. Inspect documentation, supported runtime, dependencies, configuration and acceptance checks before defining its deployment adapter."
        {'purpose'=>'Prepare repository onboarding','observation'=>value,
         'requirements'=>['Inspect the repository documentation and license','Identify runtime, dependencies and build/start commands','Define the installation target and configuration','Verify a deployment adapter and acceptance checks'],
         'command'=>{'kind'=>'ticket','text'=>description},
         'next_step'=>"This source has not been installed or enabled. /watch apply #{event.id} opens the onboarding ticket; a reviewed deployment adapter is required before installation."}
      end
    end
  end
end
