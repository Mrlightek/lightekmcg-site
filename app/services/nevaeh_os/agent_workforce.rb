# frozen_string_literal: true
module NevaehOs
  module AgentWorkforce
    module_function
    def request!(worker:,actor:,key:)
      raise ArgumentError,'Worker belongs to another account or is paused' unless worker.user_id==actor.id && worker.enabled?
      Executor.authorize_command!(actor:actor,command:worker.command.merge('agent_id'=>worker.nevaeh_os_agent_id))
      worker.with_lock do
        worker.runs.find_or_create_by!(request_key:key) { |run| run.actor=actor;run.snapshot=worker.command.merge('agent_id'=>worker.nevaeh_os_agent_id) }
      end
    end
    def execute!(run)
      run.with_lock do
        return if run.nevaeh_os_action_id
        worker=run.nevaeh_agent_worker.reload
        actor=run.actor.reload
        raise ArgumentError,'Agent worker was paused or its owner changed' unless worker.enabled? && worker.user_id==actor.id
        Agents.authorize!(run.snapshot,actor)
        action=Dispatch.submit!(actor:actor,command:run.snapshot,request_key:"agent-run-#{run.id}")
        run.update!(nevaeh_os_action:action,status:'dispatched',error:nil)
      end
    rescue ArgumentError,ActiveRecord::RecordNotFound,Gatekeeper::AuthorizationDenied,LightekPwa::Policy::Denied => error
      run.update!(status:'blocked',error:error.message)
    end
    def tick!
      now=Time.current
      NevaehAgentWorker.where(enabled:true).where('next_run_at <= ?',now).order(:next_run_at).limit(100).each do |worker|
        worker.with_lock do
          next unless worker.enabled? && worker.next_run_at && worker.next_run_at<=now && worker.interval_minutes
          last_status=worker.runs.order(id: :desc).first&.execution_status
          raise ArgumentError,'Previous agent run requires attention' if %w[failed blocked error evidence_unavailable].include?(last_status)
          raise ArgumentError,'Agent autonomy is not scheduled' unless worker.nevaeh_os_agent.reload.autonomy=='scheduled'
          request!(worker:worker,actor:worker.user.reload,key:"schedule-#{worker.next_run_at.to_i}")
          worker.update!(next_run_at:now+worker.interval_minutes.minutes)
        rescue ArgumentError,ActiveRecord::RecordNotFound,Gatekeeper::AuthorizationDenied,LightekPwa::Policy::Denied
          worker.update!(enabled:false)
        end
      end
      NevaehAgentRun.where(status:'queued').order(:id).limit(100).pluck(:id).each { |id| NevaehOs::AgentRunJob.perform_later(id) }
    end
    def create!(actor:,command:,key:)
      agent=Agents.resolve!(command.fetch('agent_ref'),actor)
      inner=command.fetch('command').merge('agent_id'=>agent.id)
      Agents.authorize!(inner,actor)
      interval=command['interval_minutes']
      agent.update!(autonomy:'scheduled') if interval && agent.autonomy!='scheduled'
      worker=NevaehAgentWorker.create!(user:actor,nevaeh_os_agent:agent,name:"#{agent.name}: #{Agents.capability(inner)}",command:inner,interval_minutes:interval)
      if interval
        {'agent_worker_id'=>worker.id,'agent'=>agent.name,'next_run_at'=>worker.next_run_at,'status'=>'scheduled'}
      else
        run=request!(worker:worker,actor:actor,key:key)
        NevaehOs::AgentRunJob.perform_later(run.id)
        {'agent_worker_id'=>worker.id,'agent_run_id'=>run.id,'agent'=>agent.name,'status'=>'queued'}
      end
    end
  end
end
