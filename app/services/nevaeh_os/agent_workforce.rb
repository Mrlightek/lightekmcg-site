# frozen_string_literal: true
require 'securerandom'
module NevaehOs
  module AgentWorkforce
    module_function
    def request!(worker:,actor:,key:,task_id:nil,dependencies:[])
      raise ArgumentError,'Worker belongs to another account or is paused' unless worker.user_id==actor.id && worker.enabled? && worker.deleted_at.nil?
      Executor.authorize_command!(actor:actor,command:worker.command.merge('agent_id'=>worker.nevaeh_os_agent_id))
      # Retrying the same delivery returns its existing reservation; a new
      # dispatch with an already reserved UUID must never become another run.
      if (existing=worker.runs.find_by(request_key:key))
        raise ArgumentError,'Task UUID is already reserved for another dispatch' if task_id && existing.task_uuid!=task_id
        return existing
      end
      task_id ||= SecureRandom.uuid
      raise ArgumentError,'Task UUID is already reserved for another dispatch' if NevaehAgentRun.exists?(task_uuid:task_id)
      raise ArgumentError,'Task UUID already exists in the report store' if ReportJournal.read!(actor).key?(task_id)
      dependencies.each { |dependency| WorkerReports.resolve!(actor:actor,dependency:dependency) }
      worker.with_lock do
        bound=DocumentationWorkers.bind!(actor:actor,command:worker.command.merge('agent_id'=>worker.nevaeh_os_agent_id))
        worker.update!(command:bound) unless worker.command==bound
      end
      WorkerReports.sweep!(actor:actor,limit:30)
      snapshot=worker.command.merge('agent_id'=>worker.nevaeh_os_agent_id)
      experience=WorkerReports.context(actor:actor,agent:worker.nevaeh_os_agent,command:snapshot)
      worker.with_lock do
        # The unique database index arbitrates concurrent reservations across
        # accounts, worker assignments and Rails/Sidekiq processes.
        if (existing=worker.runs.find_by(request_key:key))
          raise ArgumentError,'Task UUID is already reserved for another dispatch' if existing.task_uuid!=task_id
          return existing
        end
        worker.runs.create!(request_key:key) do |run|
          run.task_uuid=task_id
          run.actor=actor
          run.snapshot=snapshot.merge('experience_contract'=>WorkerReports.contract(snapshot,worker.nevaeh_os_agent),
            'manager_context'=>experience,'report_dependencies'=>dependencies)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      raise ArgumentError,'Task UUID is already reserved for another dispatch'
    end
    def execute!(run)
      run.with_lock do
        return if run.nevaeh_os_action_id
        worker=run.nevaeh_agent_worker.reload
        actor=run.actor.reload
        WorkerReports.dependencies_for(run).each { |dependency| WorkerReports.resolve!(actor:actor,dependency:dependency) }
        raise ArgumentError,'Agent worker was paused or its owner changed' unless worker.enabled? && worker.deleted_at.nil? && worker.user_id==actor.id
        Agents.authorize!(run.snapshot,actor)
        document=DocumentationWorkers.read!(actor:actor,command:run.snapshot)
        run.update!(snapshot:run.snapshot.merge('documentation_read'=>document.except(:body).stringify_keys))
        action=Dispatch.submit!(actor:actor,command:run.snapshot,request_key:"agent-run-#{run.task_uuid}")
        run.update!(nevaeh_os_action:action,status:'dispatched',error:nil)
      end
    rescue ArgumentError,ActiveRecord::RecordNotFound,SystemCallError,IOError,Gatekeeper::AuthorizationDenied,LightekPwa::Policy::Denied => error
      run.update!(status:'blocked',error:error.message)
    end
    def tick!
      now=Time.current
      NevaehAgentWorker.where(enabled:true,deleted_at:nil).where('next_run_at <= ?',now).order(:next_run_at).limit(100).each do |worker|
        worker.with_lock do
          next unless worker.enabled? && worker.deleted_at.nil? && worker.next_run_at && worker.next_run_at<=now && worker.interval_minutes
          last_status=worker.runs.order(id: :desc).first&.execution_status
          raise ArgumentError,'Previous agent run requires attention' if %w[failed blocked error evidence_unavailable needs_review cancelled].include?(last_status)
          raise ArgumentError,'Agent autonomy is not scheduled' unless worker.nevaeh_os_agent.reload.autonomy=='scheduled'
          request!(worker:worker,actor:worker.user.reload,key:"schedule-#{worker.next_run_at.to_i}")
          worker.update!(next_run_at:now+worker.interval_minutes.minutes)
        rescue ArgumentError,ActiveRecord::RecordNotFound,Gatekeeper::AuthorizationDenied,LightekPwa::Policy::Denied => error
          worker.update!(enabled:false)
          if worker.command['kind']=='growth_plan'
            Rails.logger.warn({event:'lightek.growth.schedule_paused',agent_worker_id:worker.id,actor_id:worker.user_id,site_id:worker.command['site_id'],reason:error.message.first(300)}.to_json)
          end
        end
      end
      NevaehAgentRun.where(status:'queued').order(:id).limit(100).pluck(:id).each { |id| NevaehOs::AgentRunJob.perform_later(id) }
      WorkerReports.sweep!
    end
    def create!(actor:,command:,key:)
      agent=Agents.resolve!(command.fetch('agent_ref'),actor)
      inner=DocumentationWorkers.bind!(actor:actor,command:command.fetch('command').merge('agent_id'=>agent.id))
      Agents.authorize!(inner,actor)
      interval=command['interval_minutes']
      agent.update!(autonomy:'scheduled') if interval && agent.autonomy!='scheduled'
      worker=if (inner['page_contract'] || inner['kind']=='documentation_answer') && !interval
        context=inner.dig('page_contract','context')
        name=context ? "#{PageContext.area(context)[2]} · #{Agents.capability(inner)}".first(160) : "Page SME · #{inner.fetch('topic')}"
        actor.with_lock do
          same=NevaehAgentWorker.where(user:actor,nevaeh_os_agent:agent,name:name,deleted_at:nil,interval_minutes:nil).order(id: :desc).limit(100).detect { |row| row.command==inner }
          same || NevaehAgentWorker.create!(user:actor,nevaeh_os_agent:agent,name:name,command:inner)
        end
      else
        NevaehAgentWorker.create!(user:actor,nevaeh_os_agent:agent,name:"#{agent.name}: #{Agents.capability(inner)}",command:inner,interval_minutes:interval)
      end
      if interval
        {'agent_worker_id'=>worker.id,'agent'=>agent.name,'next_run_at'=>worker.next_run_at,'status'=>'scheduled'}
      else
        run=request!(worker:worker,actor:actor,key:key)
        NevaehOs::AgentRunJob.perform_later(run.id)
        {'agent_worker_id'=>worker.id,'agent_run_id'=>run.id,'task_id'=>run.task_uuid,'agent'=>agent.name,'status'=>'queued','manager_context'=>run.snapshot['manager_context']}
      end
    end
  end
end
