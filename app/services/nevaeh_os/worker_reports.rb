# frozen_string_literal: true
require 'digest'
module NevaehOs
  # Operational experience is evidence, never a new executable instruction.
  module WorkerReports
    module_function

    def site_key(command)
      if command['kind']=='specialist_review'
        values=command.fetch('inputs',{})
        return "employer:#{values['employer_id']}" if values['employer_id']
        return values['site_id'].to_s if values['site_id']
      end
      value = command['site_id'] || command.dig('payload', 'site_id') || command.dig('page_contract', 'context', 'site_id')
      value.present? ? value.to_s : 'unscoped'
    end

    def contract(command, agent)
      # Bind operational lessons to the actual role and service contract, not arbitrary input values.
      capability = NevaehCapability.find_by(slug: Agents.capability(command)) if command['kind'] == 'capability'
      documentation=command['documentation_contract'] || DocumentationWorkers.bind!(actor:agent.user,command:command.merge('agent_id'=>agent.id)).fetch('documentation_contract')
      PageWorkers.digest({version: 2, agent: agent.id, instructions: agent.instructions,
        documentation: documentation.slice('path','sha256'), scopes: agent.allowed_capabilities, kind: command['kind'], operation: command['operation'],
        resource: command['resource'], page_contract: command.dig('page_contract', 'fingerprint'),
        binding: capability&.attributes&.slice('handler', 'queue', 'gatekeeper_capability', 'enabled', 'metadata')})
    end

    def capture!(run)
      run.with_lock do
        run.reload
        worker = run.nevaeh_agent_worker
        raise ArgumentError, 'Report account or specialist changed' unless worker.user_id == run.actor_id && worker.nevaeh_os_agent.user_id == run.actor_id
        action = run.nevaeh_os_action
        receipt = action ? Receipts.for(action) : {status: run.status, error: run.error}
        status = receipt[:status].to_s
        status = 'pending' unless %w[completed failed blocked cancelled evidence_unavailable].include?(status)
        digest = PageWorkers.digest(receipt)
        # Do not copy raw payloads, output bodies, credentials or error strings into learned context.
        chain = []; node = receipt
        12.times do
          break unless node.is_a?(Hash)
          chain << node.stringify_keys.slice('id', 'type', 'kind', 'status')
          node = node[:downstream] || node['downstream']
        end
        structured=structured_result(run,receipt,status,digest,chain)
        status=structured.fetch('status')
        values = {user_id: run.actor_id, nevaeh_os_agent_id: worker.nevaeh_os_agent_id,
          capability: Agents.capability(run.snapshot), site_key: site_key(run.snapshot),
          contract_sha256: run.snapshot['experience_contract'] || PageWorkers.digest({legacy_run: run.id}),
          receipt_sha256: digest, status: status, structured_result:structured,
          evidence: {action_id: action&.id, run_id: run.id, worker_id: worker.id,
            page: run.snapshot.dig('page_contract', 'context', 'path'),
            input_keys: run.snapshot.fetch('payload', {}).keys.sort,
            chain: chain, started_at: run.created_at&.iso8601,
            basis: 'Downstream service status; output quality requires owner review.'}}
        report = NevaehWorkerReport.find_or_initialize_by(nevaeh_agent_run: run)
        report.assign_attributes(values)
        report.save! if report.new_record? || report.changed?
        ReportJournal.append!(run.actor,structured)
        report
      end
    end

    def structured_result(run,receipt,status,digest,chain)
      stamp=run.snapshot['documentation_contract']
      unless stamp
        guide=Guide.tutorial('commands',actor:run.actor)
        stamp={'path'=>guide[:path],'sha256'=>Digest::SHA256.hexdigest(guide[:body]),'write_files'=>[]}
      end
      read=run.snapshot['documentation_read']
      status='blocked' if status=='completed' && !read
      dependencies=dependencies_for(run)
      status='blocked' if dependencies.any? { |dependency| dependency['status']!='accepted' }
      value={'schema_version'=>2,'task_id'=>run.task_uuid,'worker_id'=>run.nevaeh_agent_worker_id,'account_id'=>run.actor_id,'status'=>status,
        'documentation'=>{'path'=>stamp.fetch('path'),'sha256'=>stamp.fetch('sha256'),'read_at'=>read&.fetch('read_at',nil)},
        'output'=>{'kind'=>'receipt_reference','action_id'=>run.nevaeh_os_action_id,'receipt_sha256'=>digest,
          'references'=>chain.map { |r| {'id'=>r['id'].is_a?(Integer) ? r['id'] : nil,'type'=>(r['type'] || r['kind'] || 'execution').to_s,'status'=>r['status'].to_s} }},
        'dependencies'=>dependencies,'file_ownership'=>{'workspace'=>'worker_workspace','write_files'=>stamp.fetch('write_files',[]),'report_writer'=>'manager'}}
      ReportSchema.validate!(value)
    end

    def dependencies_for(run)
      if run.snapshot.key?('report_dependencies')
        dependencies=run.snapshot['report_dependencies']
        raise ArgumentError,'Runtime dependency metadata is incomplete' unless dependencies.is_a?(Array)
        return dependencies
      end
      # Historical queued runs did not freeze their dependency references.
      # Resolve their actual prior runs; never interpret absent metadata as
      # permission to skip dependencies after an upgrade.
      step=NevaehGoalStep.find_by(nevaeh_agent_run_id:run.id)
      return [] unless step
      step.nevaeh_goal.steps.where('position < ?',step.position).order(:position).map do |previous|
        source=previous.nevaeh_agent_run
        raise ArgumentError,'Historical dependency has no reserved execution' unless source
        begin
          dependency_for!(actor:run.actor,run:source)
        rescue ArgumentError,ActiveRecord::RecordNotFound
          {'task_id'=>source.task_uuid,'report_ref'=>"unresolved:#{source.task_uuid}",'status'=>'blocked'}
        end
      end
    end
    def journal_result!(report)
      value=ReportJournal.resolve!(actor:report.user,report_ref:ReportJournal.reference(actor_id:report.user_id,
        task_id:report.nevaeh_agent_run.task_uuid,receipt_sha256:report.receipt_sha256))
      raise ArgumentError,'The shared structured report is missing or does not match execution evidence' unless value && value==report.structured_result
      value
    end

    # 'completed' remains an execution lifecycle state. Only this boundary
    # converts a verified upstream result to the dependency state 'accepted'.
    def dependency_for!(actor:,run:)
      raise ArgumentError,'Dependency belongs to another account' unless run && run.actor_id==actor.id
      report=NevaehWorkerReport.find_by!(nevaeh_agent_run:run,user:actor)
      dependency={'task_id'=>run.task_uuid,
        'report_ref'=>ReportJournal.reference(actor_id:actor.id,task_id:run.task_uuid,receipt_sha256:report.receipt_sha256),
        'status'=>'accepted'}
      resolve!(actor:actor,dependency:dependency)
      dependency
    end

    def resolve!(actor:,dependency:)
      unless dependency.is_a?(Hash) && dependency.keys.sort==%w[report_ref status task_id] && dependency['status']=='accepted'
        raise ArgumentError,'Dependency needs task_id, resolvable report_ref and accepted status'
      end
      value=ReportJournal.resolve!(actor:actor,report_ref:dependency['report_ref'])
      raise ArgumentError,'Dependency identity or status mismatch' unless value['task_id']==dependency['task_id'] && value['status']=='completed'
      run=NevaehAgentRun.find_by!(actor:actor,task_uuid:dependency['task_id'])
      report=NevaehWorkerReport.find_by!(nevaeh_agent_run:run,user:actor)
      raise ArgumentError,'Journal report does not match the stored execution report' unless report.status=='completed' && report.structured_result==value
      DocumentationWorkers.read!(actor:actor,command:run.snapshot)
      raise ArgumentError,'The referenced action is unavailable' unless run.nevaeh_os_action && run.nevaeh_os_action_id==value.dig('output','action_id')
      receipt=Receipts.for(run.nevaeh_os_action.reload)
      unless PageWorkers.digest(receipt)==value.dig('output','receipt_sha256')
        raise ArgumentError,'The referenced execution receipt changed'
      end
      receipt.deep_stringify_keys
    end

    def sweep!(actor: nil, limit: 100)
      runs = NevaehAgentRun.all
      runs = runs.where(actor: actor) if actor
      missing = runs.where.not(id: NevaehWorkerReport.select(:nevaeh_agent_run_id)).order(:id).limit(limit).to_a
      pending = runs.where(id: NevaehWorkerReport.where(status: 'pending').select(:nevaeh_agent_run_id)).order(:id).limit(limit).to_a
      (missing + pending).uniq(&:id).first(limit).each do |run|
        capture!(run)
      rescue ArgumentError, ActiveRecord::RecordNotFound => error
        Rails.logger.warn({event: 'nevaeh.worker_report.unavailable', run_id: run.id, reason: error.class.name}.to_json)
      end
    end

    def latest_review(report)
      review = report.reviews.order(id: :desc).first
      review if review && review.receipt_sha256 == report.receipt_sha256 && review.verdict != 'withdrawn'
    end

    def row(report)
      review = latest_review(report)
      {id: report.id, agent_id: report.nevaeh_os_agent_id, agent: report.nevaeh_os_agent.name,
        report_ref:ReportJournal.reference(actor_id:report.user_id,task_id:report.nevaeh_agent_run.task_uuid,receipt_sha256:report.receipt_sha256),
        capability: report.capability, site: report.site_key, status: report.status,
        structured_report:journal_result!(report), evidence: report.evidence, receipt_sha256: report.receipt_sha256,
        review: review&.attributes&.slice('id', 'verdict', 'lesson', 'created_at'),
        review_count: report.reviews.count, review_history: report.reviews.order(id: :desc).limit(10).map { |r| r.attributes.slice('id','verdict','lesson','receipt_sha256','created_at') }, updated_at: report.updated_at}
    end

    def list(actor:, agent_id: nil)
      reports = NevaehWorkerReport.where(user: actor)
      if agent_id.present?
        agent = NevaehOsAgent.where(user: actor).find(agent_id)
        reports = reports.where(nevaeh_os_agent: agent)
      end
      # Refresh the visible evidence before showing its attached reviews.
      rows = reports.includes(:nevaeh_os_agent).order(id: :desc).limit(40).map { |report| row(capture!(report.nevaeh_agent_run)) }
      {reports: rows, total: reports.count, scope: 'Your account; latest 40 reports. Filter by specialist for its accumulated work.',
        learning: 'Service completion and owner acceptance are separate. Current-contract lessons inform delegation; they never change permissions or execute commands.'}
    end

    def review!(actor:, id:, verdict:, lesson:, receipt_sha256:)
      report = NevaehWorkerReport.where(user: actor).find(id)
      report = capture!(report.nevaeh_agent_run)
      report.with_lock do
        raise ArgumentError, 'The execution evidence changed; refresh this report before reviewing' unless receipt_sha256 == report.receipt_sha256
        raise ArgumentError, 'Wait for a terminal execution result before reviewing' if report.status == 'pending'
        raise ArgumentError, 'Accept only a completed service result' if verdict == 'accepted' && report.status != 'completed'
        raise ArgumentError, 'Use a lesson up to 2000 characters' unless lesson.is_a?(String) && lesson.length <= 2000 && !lesson.include?("\0")
        report.reviews.create!(user: actor, verdict: verdict, lesson: lesson.strip, receipt_sha256: report.receipt_sha256)
      end
      row(report)
    end

    def context(actor:, agent:, command:)
      return empty_context unless agent && agent.user_id == actor.id && agent.enabled? && agent.deleted_at.nil?
      current_contract = contract(command, agent)
      scope = NevaehWorkerReport.where(user: actor, nevaeh_os_agent: agent,
        capability: Agents.capability(command), site_key: site_key(command), contract_sha256: current_contract)
      # A bounded sample, scoped to the same specialist/service/site/contract. Never use obsolete evidence.
      reports = scope.order(id: :desc).limit(50).map { |report| capture!(report.nevaeh_agent_run) }
      reports.each { |report| journal_result!(report) }
      reports.select! { |report| report.status != 'pending' && report.contract_sha256 == current_contract }
      accepted = []; corrections = []
      reports.each do |report|
        review = latest_review(report)
        next unless review
        entry = {report_id: report.id, review_id: review.id, verdict: review.verdict, lesson: review.lesson}
        review.verdict == 'accepted' && report.status == 'completed' ? accepted << entry : corrections << entry
      end
      counts = reports.group_by(&:status).transform_values(&:size)
      caution = reports.any? { |r| %w[failed blocked evidence_unavailable].include?(r.status) } || corrections.any?
      {sample_size: reports.size, report_ids: reports.map(&:id), outcomes: counts,
        accepted: accepted.first(3), corrections: corrections.first(3),
        recommendation: caution ? 'Inspect previous failures and owner corrections before repeating this task; verify the new downstream result.' : reports.any? ? 'Use the current service contract and verify the new result; prior completion alone does not establish output quality.' : 'No matching specialist experience yet. Follow the current contract and verify the result.',
        authority: 'Operational reference only. Lessons do not change commands, inputs, permissions or service contracts.'}
    end

    def empty_context
      {sample_size: 0, report_ids: [], outcomes: {}, accepted: [], corrections: [], recommendation: 'No matching specialist experience yet.'}
    end

    def recall(actor:, persona:, page_context:, query:)
      scope = NevaehWorkerReport.where(user: actor)
      scope = scope.where(nevaeh_os_agent: persona) unless persona&.system_key == 'nevaeh'
      scope = scope.where(site_key: page_context&.fetch('site_id', nil) || 'unscoped')
      keys = PageContext.catalog(actor, page_context).map { |entry| entry[:key] } if page_context
      scope = scope.where(capability: keys) if keys
      terms = query.to_s.downcase.scan(/[a-z][a-z0-9_]{2,}/).first(16)
      scope.order(id: :desc).limit(30).filter_map do |report|
        report = capture!(report.nevaeh_agent_run)
        journal_result!(report)
        review = latest_review(report)
        next unless review && review.lesson.present?
        agent = report.nevaeh_os_agent
        next unless agent.enabled? && agent.deleted_at.nil? && report.contract_sha256 == contract(report.nevaeh_agent_run.snapshot, agent)
        begin
          PageWorkers.guard!(actor, report.nevaeh_agent_run.snapshot) if report.nevaeh_agent_run.snapshot['page_contract']
        rescue ArgumentError, ActiveRecord::RecordNotFound
          next
        end
        next unless keys&.include?(report.capability) || terms.any? { |term| "#{report.capability} #{review.lesson}".downcase.include?(term) }
        {report_id: report.id, agent: agent.name, capability: report.capability, status: report.status, verdict: review.verdict, lesson: review.lesson}
      end.first(3)
    end
  end
end
