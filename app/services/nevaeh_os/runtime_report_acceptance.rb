# frozen_string_literal: true
module NevaehOs
  # Opt-in deployed acceptance: two read-only services, the real queues and
  # Gatekeeper, plus removal/restoration of this test's own journal entry only.
  class RuntimeReportAcceptance
    def initialize(actor:,timeout:180)
      raise ArgumentError,'Use an authorized super-admin acceptance account' unless actor.role=='super_admin'
      @actor=actor;@timeout=timeout
    end

    def wait_for!(label)
      deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+@timeout
      loop do
        result=yield
        return result if result
        raise ArgumentError,"Timed out waiting for #{label}" if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
        sleep 1
      end
    end

    def remove_entry!(uuid)
      removed=[]
      File.open(ReportJournal.path(@actor),File::RDWR|File::NOFOLLOW) do |file|
        file.flock(File::LOCK_EX)
        lines=file.readlines
        retained=lines.reject do |line|
          match=JSON.parse(line).fetch('task_id')==uuid
          removed<<line if match
          match
        end
        raise ArgumentError,'Acceptance journal entry is absent before tampering' if removed.empty?
        ReportJournal.directories!(backup_root)
        @backup_path=backup_root.join("#{uuid}-removed-entry.jsonl")
        File.open(@backup_path,File::WRONLY|File::CREAT|File::EXCL|File::NOFOLLOW,0600) do |backup|
          backup.write(removed.join);backup.flush;backup.fsync
        end
        @removed_entry_lines=removed
        file.rewind;file.write(retained.join);file.truncate(file.pos);file.flush;file.fsync
      end
      removed
    end

    def backup_root = Rails.root.join('storage','nevaeh_acceptance')

    def restore_entry!(lines)
      File.open(ReportJournal.path(@actor),File::RDWR|File::NOFOLLOW) do |file|
        file.flock(File::LOCK_EX)
        file.seek(0,IO::SEEK_END);file.write(lines.join);file.flush;file.fsync
      end
    end

    def run!
      goal=Goals.create!(actor:@actor,request_key:SecureRandom.uuid,values:{'title'=>'Live journal authority and one-edge acceptance','steps'=>[
        {'key'=>'list','agent'=>'nevaeh','command'=>'/read agents'},
        {'key'=>'read','agent'=>'nevaeh','command'=>{'kind'=>'resource','operation'=>'read','resource'=>'agents',
          'id'=>{'$step'=>'list','path'=>'result.records.0.id'}}}
      ]})
      # Hold the goal lock while pausing so the minute sweep cannot dispatch
      # step two before the negative test has removed the source entry.
      goal.with_lock do
        Goals.control!(goal:goal,actor:@actor,operation:'start')
        Goals.tick!(goal)
        goal.update!(status:'paused')
      end
      first=goal.steps.order(:position).first
      source=first.reload.nevaeh_agent_run
      wait_for!('upstream Dispatch completion') do
        state=source.reload.execution_status
        raise ArgumentError,"Upstream failed: #{state}" if %w[failed blocked cancelled evidence_unavailable].include?(state)
        state=='completed'
      end
      goal.with_lock do
        goal.update!(status:'running');Goals.tick!(goal);goal.update!(status:'paused')
      end
      first.reload
      raise ArgumentError,'Upstream goal output checks did not complete' unless first.status=='completed'
      reference=WorkerReports.dependency_for!(actor:@actor,run:source)
      expected=WorkerReports.resolve!(actor:@actor,dependency:reference).dig('result','records',0,'id')
      raise ArgumentError,'Upstream output must be an integer' unless expected.is_a?(Integer)
      cached=first.evidence.deep_dup
      begin
        first.update!(evidence:{'result'=>{'records'=>[{'id'=>-999}]}})
        resolved=Goals.resolve(goal.steps.order(:position).last.command,goal)
        raise ArgumentError,'Manager used cached goal evidence' unless resolved['id']==expected
        remove_entry!(source.task_uuid)
        raise ArgumentError,'Journal entry still resolves after removal' if ReportJournal.read!(@actor,task_id:source.task_uuid).key?(source.task_uuid)
        begin
          WorkerReports.resolve!(actor:@actor,dependency:reference)
          raise 'Missing journal entry incorrectly resolved'
        rescue ArgumentError
          # Expected: no DB, cached step, file-store or legacy run-N fallback.
        end
        goal.with_lock do
          goal.update!(status:'running');Goals.tick!(goal)
        end
        last=goal.steps.order(:position).last.reload
        unless goal.reload.status=='blocked' && last.nevaeh_agent_run_id.nil?
          raise ArgumentError,'Missing journal entry did not block dependent dispatch'
        end
      ensure
        begin
          restore_entry!(@removed_entry_lines) if @removed_entry_lines&.any?
        ensure
          first.update!(evidence:cached)
        end
      end
      WorkerReports.resolve!(actor:@actor,dependency:reference)
      Goals.control!(goal:goal,actor:@actor,operation:'resume')
      tick_at=0
      wait_for!('dependent Dispatch completion') do
        if Time.now.to_i>=tick_at
          GoalTickJob.perform_later(goal.id);tick_at=Time.now.to_i+5
        end
        state=goal.reload.status
        raise ArgumentError,"Dependent goal failed: #{state}" if %w[blocked cancelled].include?(state)
        state=='completed'
      end
      last=goal.steps.order(:position).last
      dependent=last.nevaeh_agent_run
      report=WorkerReports.journal_result!(NevaehWorkerReport.find_by!(nevaeh_agent_run:dependent))
      raise ArgumentError,'Resolved UUID dependency was not retained' unless report['dependencies']==[reference]
      actual=dependent.nevaeh_os_action.result.dig('records',0,'id')
      raise ArgumentError,'Dependent output differs from journal-derived input' unless actual==expected && dependent.snapshot['id']==expected
      {status:'passed',goal_id:goal.id,upstream_task_id:source.task_uuid,downstream_task_id:dependent.task_uuid,
        dependency:reference,typed_value:expected,cache_tamper_ignored:true,missing_entry_blocked_dispatch:true,
        entry_restored:true,goal_status:goal.status,source_report_remained_in_database:true}
    end
  end
end
