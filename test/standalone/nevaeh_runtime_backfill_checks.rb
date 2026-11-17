require_relative 'nevaeh_runtime_report_parity_checks'
require File.join(ROOT,'app/services/nevaeh_os/legacy_report_backfill')
require File.join(ROOT,'app/services/nevaeh_os/runtime_report_acceptance')
eval(File.read(File.join(ROOT,'db/migrate/20261116040001_backfill_nevaeh_report_references.rb')).sub('Migration[8.0]','Migration[7.2]'),TOPLEVEL_BINDING,'backfill_nevaeh_report_references')

class NevaehRuntimeBackfillChecks < NevaehRuntimeReportParityChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)

  def legacy_fixture
    plan=read_plan
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start')
    2.times { complete_current(plan) }
    runs=plan.steps.order(:position).map(&:nevaeh_agent_run)
    lines=runs.map do |run|
      report=NevaehWorkerReport.find_by!(nevaeh_agent_run:run)
      value=report.structured_result.deep_dup
      value['schema_version']=1;value['task_id']="run-#{run.id}"
      value['dependencies']=value['dependencies'].map do |d|
        source=NevaehAgentRun.find_by!(task_uuid:d['task_id'])
        {'task_id'=>"run-#{source.id}",'status'=>'completed'}
      end
      report.update_columns(structured_result:value)
      run.update!(snapshot:run.snapshot.except('report_dependencies'))
      JSON.generate(value)+"\n"
    end
    File.write(NevaehOs::ReportJournal.path(@actor),lines.join)
    [plan,runs,lines]
  end

  def test_populated_uuid_migration_backfills_every_legacy_row_before_not_null
    worker=NevaehAgentWorker.create!(user:@actor,nevaeh_os_agent:NevaehOs::Agents.resolve!('nevaeh',@actor),name:'Legacy worker',command:command('/read agents'))
    ReserveNevaehTaskUuids.new.migrate(:down)
    NevaehAgentRun.reset_column_information
    2.times do |i|
      NevaehAgentRun.insert_all!([{actor_id:@actor.id,nevaeh_agent_worker_id:worker.id,request_key:"legacy-#{i}",status:'queued',snapshot:worker.command,created_at:Time.current,updated_at:Time.current}])
    end
    ids=NevaehAgentRun.order(:id).pluck(:id)
    ReserveNevaehTaskUuids.new.migrate(:up)
    NevaehAgentRun.reset_column_information
    assert_equal ids,NevaehAgentRun.order(:id).pluck(:id)
    uuids=NevaehAgentRun.pluck(:task_uuid)
    assert_equal 2,uuids.uniq.size
    uuids.each { |uuid| assert_match(/\A[0-9a-f-]{36}\z/,uuid) }
    refute NevaehAgentRun.columns_hash.fetch('task_uuid').null
  end

  def test_migration_maps_all_legacy_edges_and_queued_snapshots_without_reassigning_uuids
    _,runs,lines=legacy_fixture
    mapping=runs.to_h { |r| [r.id,r.task_uuid] }
    BackfillNevaehReportReferences.new.migrate(:up)
    runs.each do |run|
      assert_equal mapping[run.id],run.reload.task_uuid
      report=NevaehWorkerReport.find_by!(nevaeh_agent_run:run)
      assert_equal 2,report.structured_result['schema_version']
      assert_equal run.task_uuid,report.structured_result['task_id']
      assert_equal report.structured_result,NevaehOs::WorkerReports.journal_result!(report)
    end
    dependent=runs.last.reload.snapshot['report_dependencies'].first
    assert_equal runs.first.task_uuid,dependent['task_id']
    assert_equal 'accepted',dependent['status']
    assert_match(/\Ajournal:/,dependent['report_ref'])
    actual=NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependent)
    assert_kind_of Integer,actual.dig('result','records',0,'id')
    assert File.read(NevaehOs::ReportJournal.path(@actor)).start_with?(lines.join)
    bytes=File.binread(NevaehOs::ReportJournal.path(@actor))
    BackfillNevaehReportReferences.new.migrate(:up)
    assert_equal bytes,File.binread(NevaehOs::ReportJournal.path(@actor))
    assert_equal mapping,NevaehAgentRun.where(id:mapping.keys).pluck(:id,:task_uuid).to_h
  end

  def test_missing_legacy_journal_cannot_be_promoted_from_database_or_cache
    _,runs,lines=legacy_fixture
    File.write(NevaehOs::ReportJournal.path(@actor),lines.last)
    BackfillNevaehReportReferences.new.migrate(:up)
    runs.each { |run| assert_equal 'blocked',NevaehWorkerReport.find_by!(nevaeh_agent_run:run).status }
    assert_equal 'blocked',runs.last.reload.snapshot['report_dependencies'].first['status']
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:runs.first) }
  end

  def test_retry_after_partial_journal_publication_keeps_uuid_mapping_and_is_idempotent
    _,runs,_=legacy_fixture
    mapping=runs.map(&:task_uuid)
    original=NevaehOs::ReportJournal.method(:append!)
    count=0
    NevaehOs::ReportJournal.stub(:append!,lambda { |actor,value|
      count+=1
      raise IOError,'Interrupted backfill' if count==2
      original.call(actor,value)
    }) { assert_raises(IOError) { BackfillNevaehReportReferences.new.migrate(:up) } }
    assert_equal 1,NevaehWorkerReport.find_by!(nevaeh_agent_run:runs.first).structured_result['schema_version']
    BackfillNevaehReportReferences.new.migrate(:up)
    assert_equal mapping,runs.map { |r| r.reload.task_uuid }
    assert_equal 'accepted',runs.last.reload.snapshot['report_dependencies'].first['status']
  end

  def test_partial_receipt_window_is_blocked_without_crashing_backfill_or_dispatch
    _,runs,_=legacy_fixture
    NevaehWorkerReport.find_by!(nevaeh_agent_run:runs.first).update_columns(structured_result:{})
    File.unlink(NevaehOs::ReportJournal.path(@actor))
    runs.last.update!(snapshot:runs.last.snapshot.merge('report_dependencies'=>nil))
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.dependencies_for(runs.last) }
    BackfillNevaehReportReferences.new.migrate(:up)
    assert_equal 'blocked',runs.last.reload.snapshot['report_dependencies'].first['status']
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:runs.last.snapshot['report_dependencies'].first) }
  end

  def test_runtime_reference_does_not_fall_back_to_harness_files_or_legacy_id
    _,source=finish_first
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    File.unlink(NevaehOs::ReportJournal.path(@actor))
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency) }
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency.merge('report_ref'=>".nevaeh/reports/#{source.task_uuid}.json")) }
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency.merge('report_ref'=>"run-#{source.id}")) }
  end

  def test_exact_reference_resolution_streams_old_entries_beyond_recent_tail
    _,source=finish_first
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    template=NevaehWorkerReport.find_by!(nevaeh_agent_run:source).structured_result
    4.times { NevaehOs::ReportJournal.append!(@actor,template.merge('task_id'=>SecureRandom.uuid)) }
    old=NevaehOs::ReportJournal::MAX_READ
    NevaehOs::ReportJournal.send(:remove_const,:MAX_READ)
    NevaehOs::ReportJournal.const_set(:MAX_READ,100)
    begin
      assert_kind_of Hash,NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency)
    ensure
      NevaehOs::ReportJournal.send(:remove_const,:MAX_READ)
      NevaehOs::ReportJournal.const_set(:MAX_READ,old)
    end
  end

  def test_live_probe_removes_only_its_own_entry_and_restores_it_from_durable_backup
    _,source=finish_first
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    other=NevaehWorkerReport.find_by!(nevaeh_agent_run:source).structured_result.merge('task_id'=>SecureRandom.uuid)
    NevaehOs::ReportJournal.append!(@actor,other)
    helper=NevaehOs::RuntimeReportAcceptance.new(actor:@actor)
    Dir.mktmpdir do |directory|
      helper.define_singleton_method(:backup_root) { Pathname.new(directory) }
      removed=helper.remove_entry!(source.task_uuid)
      assert File.file?(helper.instance_variable_get(:@backup_path))
      assert_equal other,NevaehOs::ReportJournal.read!(@actor)[other['task_id']]
      assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency) }
      helper.restore_entry!(removed)
      assert_kind_of Hash,NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency)
    end
  end

  def test_removed_uuid_entry_never_falls_back_to_retained_run_n_audit_history
    _,runs,_=legacy_fixture
    BackfillNevaehReportReferences.new.migrate(:up)
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:runs.first)
    helper=NevaehOs::RuntimeReportAcceptance.new(actor:@actor)
    Dir.mktmpdir do |directory|
      helper.define_singleton_method(:backup_root) { Pathname.new(directory) }
      removed=helper.remove_entry!(runs.first.task_uuid)
      begin
        assert NevaehOs::ReportJournal.read!(@actor,full:true).key?("run-#{runs.first.id}")
        assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency) }
      ensure
        helper.restore_entry!(removed)
      end
    end
  end
end
