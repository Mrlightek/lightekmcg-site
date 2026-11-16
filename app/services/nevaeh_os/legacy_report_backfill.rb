# frozen_string_literal: true
module NevaehOs
  module LegacyReportBackfill
    module_function

    def run!
      NevaehAgentRun.distinct.pluck(:actor_id).each { |id| for_actor!(User.find(id)) }
    end

    def for_actor!(actor)
      actor.with_lock do
        runs=NevaehAgentRun.where(actor:actor).order(:id).index_by(&:id)
        reports=NevaehWorkerReport.where(user:actor).index_by(&:nevaeh_agent_run_id)
        journal=ReportJournal.read!(actor,full:true)
        legacy=reports.select { |_id,report| report.structured_result['schema_version']==1 }
        converted={}
        legacy.each do |id,report|
          run=runs.fetch(id)
          value=report.structured_result.deep_dup
          ReportSchema.validate!(value)
          raise ArgumentError,'Legacy report account/run mismatch' unless value['account_id']==actor.id && value['task_id']=="run-#{id}"
          value['schema_version']=2
          value['task_id']=run.task_uuid
          # Missing/mismatched journal data never becomes accepted merely
          # because a database receipt still exists during the upgrade.
          value['status']='blocked' unless journal["run-#{id}"]==report.structured_result
          converted[id]=value
        end
        dependency=lambda do |old|
          id=old.fetch('task_id').match(/\Arun-([1-9][0-9]*)\z/)&.[](1)&.to_i
          if id
            source=runs[id]
            raise ArgumentError,'Legacy dependency has no same-account UUID mapping' unless source
            report=reports[id]
            value=converted[id] || report&.structured_result
            status=value&.fetch('status',nil)
            verified=report && value && (converted.key?(id) || journal[source.task_uuid]==value)
            if verified
              {'task_id'=>source.task_uuid,'report_ref'=>ReportJournal.reference(actor_id:actor.id,task_id:source.task_uuid,receipt_sha256:report.receipt_sha256),
                'status'=>status=='completed' ? 'accepted' : status=='failed' ? 'failed' : 'blocked'}
            else
              {'task_id'=>source.task_uuid,'report_ref'=>"unresolved:#{source.task_uuid}",'status'=>'blocked'}
            end
          else
            old # Already UUID-based; validate below without changing identity.
          end
        end
        # A blocked historical prerequisite must propagate through the full
        # chain regardless of database row order. No new completion is invented.
        (converted.size+1).times do
          changed=false
          converted.each do |id,value|
            deps=legacy.fetch(id).structured_result.fetch('dependencies').map(&dependency)
            if deps.any? { |d| d['status']!='accepted' } && value['status']!='blocked'
              value['status']='blocked';changed=true
            end
            value['dependencies']=deps
          end
          break unless changed
        end
        converted.each do |id,value|
          ReportSchema.validate!(value)
          # Persist and verify mapped journal entries before updating DB views.
          # A retry after a failed DB transaction reuses the same UUIDs/bytes.
          ReportJournal.append!(actor,value)
          raise ArgumentError,'Mapped journal report failed read-back' unless ReportJournal.read!(actor)[value['task_id']]==value
          reports.fetch(id).update!(structured_result:value,status:value['status'])
        end
        runs.each_value do |run|
          snapshot=run.snapshot.deep_dup
          if snapshot['report_dependencies'].is_a?(Array)
            deps=snapshot.fetch('report_dependencies').map(&dependency)
          elsif (report=legacy[run.id])
            deps=report.structured_result.fetch('dependencies').map(&dependency)
          elsif (step=NevaehGoalStep.find_by(nevaeh_agent_run_id:run.id))
            deps=step.nevaeh_goal.steps.where('position < ?',step.position).where.not(nevaeh_agent_run_id:nil).order(:position).map do |previous|
              dependency.call({'task_id'=>"run-#{previous.nevaeh_agent_run_id}"})
            end
          else
            deps=[]
          end
          snapshot['report_dependencies']=deps
          run.update!(snapshot:snapshot) unless run.snapshot==snapshot
        end
      end
    end
  end
end
