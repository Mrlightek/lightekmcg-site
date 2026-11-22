# frozen_string_literal: true
require 'digest'
module NevaehOs
  module Goals
    KINDS=%w[public_relations website_page website_marketing specialist_review documentation_answer production campaign_produce marketing_kit feature_showcase marketing_follow_up backlink_draft growth_plan growth_review capability console ubuntu application resource run worker_status project ticket build activate approve train checkpoint write model learn review forget improve].freeze
    FAILURES=%w[failed blocked error cancelled needs_attention needs_review evidence_unavailable stale].freeze
    WAITING=%w[pending queued running dispatched processing publishing training].freeze
    module_function
    def owned!(actor,id) = NevaehGoal.where(user:actor).find(id)
    def references(value,&block)
      case value
      when Hash
        if value.key?('$step')
          raise ArgumentError,'A step reference needs only $step and path' unless value.keys.sort==%w[$step path]
          block.call(value)
        else value.each_value { |child| references(child,&block) }
        end
      when Array then value.each { |child| references(child,&block) }
      end
    end
    def create!(actor:,values:,request_key:,host:nil,origin:nil)
      raise ArgumentError,'Goal inputs must be an object' unless values.is_a?(Hash)
      data=values.deep_stringify_keys
      raise ArgumentError,'Use title and steps for a goal' unless (data.keys-%w[title steps]).empty?
      rows=data.fetch('steps');raise ArgumentError,'A goal needs 1–12 concrete steps' unless rows.is_a?(Array) && rows.size.between?(1,12) && data.to_json.bytesize<=24000
      digest=Digest::SHA256.hexdigest(data.to_json)
      if (old=NevaehGoal.find_by(user:actor,request_key:request_key))
        raise ArgumentError,'This goal request belongs to different inputs' unless old.fingerprint==digest
        return old
      end
      Workforce.install!(actor)
      seen=[]
      compiled=rows.each_with_index.map do |row,index|
        raise ArgumentError,'Use key, label, agent, command and expectations per step' unless row.is_a?(Hash) && (row.keys-%w[key label agent command expectations]).empty?
        key=row.fetch('key',"step_#{index+1}")
        raise ArgumentError,'Use unique lowercase step keys' unless key.is_a?(String) && key.match?(/\A[a-z][a-z0-9_]{0,39}\z/) && !seen.include?(key)
        agent=Agents.resolve!(row.fetch('agent'),actor)
        command=row.fetch('command');command=Command.parse(command) if command.is_a?(String)
        raise ArgumentError,'Choose a supported executable command for each step' unless command.is_a?(Hash) && KINDS.include?(command['kind'])
        command=command.except('agent_id','persona_id')
        has_refs=false
        references(command) do |ref|
          has_refs=true
          raise ArgumentError,'Step references must name an earlier step and a bounded evidence path' unless seen.include?(ref['$step']) && ref['path'].is_a?(String) && ref['path'].match?(/\A(?:result|downstream)(?:\.[a-zA-Z0-9_]+){1,8}\z/)
        end
        # Native capabilities must retain a trusted site origin for future reference expansion.
        command = PublicRelations.bind(actor, command.except('delegation_id')) if command['kind'] == 'public_relations'
        command = WebsiteMarketing.bind(actor, command.except('delegation_id')) if command['kind'] == 'website_marketing'
        if command['kind']=='capability'
          command['origin']=origin
          command['site_id']||=command.dig('payload','site_id')
        end
        unless has_refs
          command=Conversation.new(actor:actor,host:host,origin:origin).prepare_command(command)
          Executor.authorize_command!(actor:actor,command:command.merge('agent_id'=>agent.id))
        end
        checks=row.fetch('expectations',[])
        raise ArgumentError,'Use at most eight literal output expectations' unless checks.is_a?(Array) && checks.size<=8 && checks.all? { |c| c.is_a?(Hash) && (c.keys-%w[path equals present]).empty? && c['path'].is_a?(String) && c['path'].match?(/\A(?:result|downstream)(?:\.[a-zA-Z0-9_]+){1,8}\z/) && (c.key?('equals') || c['present']==true) }
        seen<<key
        {key:key,label:row.fetch('label',key.humanize),position:index,nevaeh_os_agent:agent,command:command,expectations:checks}
      end
      NevaehGoal.transaction do
        goal=NevaehGoal.create!(user:actor,title:data.fetch('title'),request_key:request_key,fingerprint:digest)
        compiled.each { |step| goal.steps.create!(step) }
        goal
      end
    rescue KeyError=>error
      raise ArgumentError,"Missing goal input: #{error.key}"
    end
    def control!(goal:,actor:,operation:)
      owned!(actor,goal.id)
      goal.with_lock do
        case operation
        when 'start','resume'
          raise ArgumentError,'Completed or cancelled goals cannot be resumed' if %w[completed cancelled].include?(goal.status)
          goal.update!(status:'running',error:nil)
        when 'pause' then goal.update!(status:'paused') unless %w[completed cancelled].include?(goal.status)
        when 'cancel'
          goal.steps.each do |step|
            worker=step.nevaeh_agent_run&.nevaeh_agent_worker
            Workforce.remove_worker!(actor,worker.id) if worker
          end
          goal.update!(status:'cancelled') unless goal.status=='completed'
        else raise ArgumentError,'Choose start, resume, pause or cancel'
        end
      end
      GoalTickJob.perform_later(goal.id) if goal.status=='running'
      goal
    end
    def dig_path(value,path)
      path.split('.').reduce(value) { |at,key| at.is_a?(Hash) ? (at.key?(key) ? at[key] : at[key.to_sym]) : at.is_a?(Array) && key.match?(/\A\d+\z/) ? at[key.to_i] : nil }
    end
    def resolve(value,goal)
      case value
      when Hash
        if value.key?('$step')
          source=goal.steps.find_by!(key:value.fetch('$step'))
          raise ArgumentError,'Referenced step has not completed' unless source.status=='completed'
          dependency=WorkerReports.dependency_for!(actor:goal.user,run:source.nevaeh_agent_run)
          receipt=WorkerReports.resolve!(actor:goal.user,dependency:dependency)
          result=dig_path(receipt,value.fetch('path'))
          raise ArgumentError,'Required output is missing from the completed step' if result.nil?
          result
        else value.transform_values { |item| resolve(item,goal) }
        end
      when Array then value.map { |item| resolve(item,goal) }
      else value
      end
    end
    def verdict(receipt,command,expectations)
      node=receipt.deep_stringify_keys
      loop do
        status=node['status'].to_s
        return ['blocked',node['error'].presence || "Downstream state: #{status}"] if FAILURES.include?(status)
        return ['waiting',nil] if WAITING.include?(status)
        result=node['result']
        if result.is_a?(Hash)
          return ['blocked',result['error'].presence || "Reported result: #{result['status']}"] if result['success']==false || FAILURES.include?(result['status'])
          return ['waiting',nil] if !node['downstream'] && WAITING.include?(result['status'])
        end
        break unless node['downstream'].is_a?(Hash)
        node=node['downstream']
      end
      return ['blocked','The task has no confirmed completion evidence'] unless %w[completed verified done ready published active].include?(node['status'].to_s)
      root=receipt.deep_stringify_keys
      if command['kind']=='build'
        return ['blocked','The constructed release did not pass its saved acceptance examples'] unless %w[verified active].include?(root.dig('result','status')) && Array(root.dig('result','verification','samples')).any? && root.dig('result','verification','samples').all? { |r| r['passed']==true }
      elsif command['kind']=='train'
        return ['blocked','Native training did not pass acceptance'] unless node.dig('metrics','acceptance_passed')==true
      end
      expectations.each do |check|
        actual=dig_path(root,check.fetch('path'))
        return ['blocked',"Output check failed: #{check['path']}"] if (check['present'] && actual.nil?) || (check.key?('equals') && actual!=check['equals'])
      end
      ['completed',nil]
    end
    def tick!(goal)
      goal.with_lock do
        return unless goal.status=='running'
        step=goal.steps.where.not(status:'completed').order(:position).first
        return goal.update!(status:'completed',error:nil) unless step
        agent=step.nevaeh_os_agent.reload
        raise ArgumentError,'The assigned specialist was paused or deleted' unless agent.enabled? && agent.deleted_at.nil?
        if step.nevaeh_agent_run
          run=step.nevaeh_agent_run
          worker=run.nevaeh_agent_worker.reload
          raise ArgumentError,'The assigned task was paused or deleted' unless worker.enabled? && worker.deleted_at.nil?
          receipt=run.nevaeh_os_action ? Receipts.for(run.nevaeh_os_action) : {status:run.status,error:run.error}
          result,error=verdict(receipt,step.command,step.expectations)
          if result=='blocked'
            step.update!(status:'blocked',evidence:receipt,error:error);goal.update!(status:'blocked',error:error)
          elsif result=='completed'
            # Publish, fsync and read back the report before accepting this
            # step or allowing the next step to consume its output.
            report=WorkerReports.capture!(run)
            raise ArgumentError,'Worker report is not complete' unless WorkerReports.journal_result!(report)['status']=='completed'
            step.update!(status:'completed',evidence:receipt,error:nil)
            goal.update!(status:'completed',error:nil) unless goal.steps.where.not(status:'completed').exists?
          else step.update!(evidence:receipt)
          end
        else
          dependencies=goal.steps.where('position < ?',step.position).order(:position).map do |previous|
            raise ArgumentError,'Dependency step has not completed' unless previous.status=='completed'
            WorkerReports.dependency_for!(actor:goal.user,run:previous.nevaeh_agent_run)
          end
          command=resolve(step.command,goal).merge('agent_id'=>agent.id)
          Executor.authorize_command!(actor:goal.user.reload,command:command)
          worker=NevaehAgentWorker.create!(user:goal.user,nevaeh_os_agent:agent,name:"#{goal.title.first(95)} · #{step.label.first(55)}",command:command)
          run=AgentWorkforce.request!(worker:worker,actor:goal.user,key:"goal-step-#{step.id}",dependencies:dependencies)
          step.update!(status:'running',nevaeh_agent_run:run,error:nil)
          AgentRunJob.perform_later(run.id)
        end
      rescue ArgumentError,ActiveRecord::RecordNotFound,ActiveRecord::RecordInvalid,ActiveRecord::RecordNotUnique,SystemCallError,IOError,Gatekeeper::AuthorizationDenied,CanCan::AccessDenied,LightekPwa::Policy::Denied => error
        step&.update!(status:'blocked',error:error.message.first(2000));goal.update!(status:'blocked',error:error.message.first(2000))
      end
    end
    def sweep!
      NevaehGoal.where(status:'running').order(:id).limit(100).pluck(:id).each { |id| GoalTickJob.perform_later(id) }
    end
    def receipt(goal)
      {id:goal.id,title:goal.title,status:goal.status,error:goal.error,steps:goal.steps.map { |s| {id:s.id,key:s.key,label:s.label,agent:s.nevaeh_os_agent.name,status:s.status,command:s.command,expectations:s.expectations,error:s.error,evidence:s.evidence} },completion_basis:'Every task must report downstream completion and pass its configured output checks. Artistic quality and unsupported integrations are not inferred from a successful submission.'}
    end
  end
end
