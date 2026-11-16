require_relative 'nevaeh_workforce_goal_checks'

class NevaehRuntimeReportParityChecks < NevaehWorkforceGoalChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)

  def read_plan
    goal({'title'=>'Resolve a committed runtime report','steps'=>[
      {'key'=>'list','agent'=>'nevaeh','command'=>'/read agents'},
      {'key'=>'read','agent'=>'nevaeh','command'=>{'kind'=>'resource','operation'=>'read','resource'=>'agents',
        'id'=>{'$step'=>'list','path'=>'result.records.0.id'}}}
    ]})
  end

  def finish_first
    plan=read_plan
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start')
    complete_current(plan)
    [plan,plan.steps.order(:position).first.nevaeh_agent_run]
  end

  def test_manager_uuid_reservation_is_durable_unique_and_immutable_before_execution
    worker=NevaehAgentWorker.create!(user:@actor,nevaeh_os_agent:NevaehOs::Agents.resolve!('nevaeh',@actor),
      name:'Reserved read',command:command('/read agents'))
    uuid=SecureRandom.uuid
    run=NevaehOs::AgentWorkforce.request!(worker:worker,actor:@actor,key:'first-dispatch',task_id:uuid)
    assert_equal uuid,NevaehAgentRun.find(run.id).task_uuid
    assert_nil run.nevaeh_os_action_id
    assert_equal run.id,NevaehOs::AgentWorkforce.request!(worker:worker,actor:@actor,key:'first-dispatch',task_id:uuid).id
    assert_raises(ArgumentError) { NevaehOs::AgentWorkforce.request!(worker:worker,actor:@actor,key:'second-dispatch',task_id:uuid) }
    other_worker=NevaehAgentWorker.create!(user:@actor,nevaeh_os_agent:worker.nevaeh_os_agent,
      name:'Another assignment',command:command('/read agents'))
    assert_raises(ArgumentError) { NevaehOs::AgentWorkforce.request!(worker:other_worker,actor:@actor,key:'different-worker',task_id:uuid) }
    assert_equal 0,other_worker.runs.count
    assert_equal 1,worker.runs.count
    assert_raises(ActiveRecord::RecordInvalid) { run.update!(task_uuid:SecureRandom.uuid) }
    # Bypass model validation to exercise the cross-process database arbiter.
    duplicate=run.reload.attributes.except('id').merge('request_key'=>'racing-dispatch')
    assert_raises(ActiveRecord::RecordNotUnique) { NevaehAgentRun.insert_all!([duplicate]) }
  end

  def test_dependency_resolves_journal_and_receipt_not_cached_step_evidence
    plan,source=finish_first
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    assert_equal source.task_uuid,dependency['task_id']
    assert_equal 'accepted',dependency['status']
    assert_match(/\Ajournal:#{@actor.id}:#{source.task_uuid}:[0-9a-f]{64}\z/,dependency['report_ref'])
    actual=source.nevaeh_os_action.result.fetch('records').first.fetch('id')
    plan.steps.first.update!(evidence:{'result'=>{'records'=>[{'id'=>-999}]}})
    NevaehOs::Goals.tick!(plan.reload)
    dependent=plan.steps.order(:position).last.nevaeh_agent_run
    assert_equal actual,dependent.snapshot['id']
    assert_kind_of Integer,dependent.snapshot['id']
    assert_equal [dependency],dependent.snapshot['report_dependencies']
    NevaehOs::AgentWorkforce.execute!(dependent)
    execute(dependent.reload.nevaeh_os_action)
    NevaehOs::Goals.tick!(plan.reload)
    assert_equal 'completed',plan.reload.status
    report=NevaehOs::WorkerReports.capture!(dependent)
    assert_equal [dependency],report.structured_result['dependencies']
    assert_equal report.structured_result,NevaehOs::ReportJournal.resolve!(actor:@actor,
      report_ref:NevaehOs::WorkerReports.row(report)[:report_ref])
  end

  def test_missing_report_blocks_before_creating_or_dispatching_dependent_run
    plan,source=finish_first
    File.unlink(NevaehOs::ReportJournal.path(@actor))
    before=[NevaehAgentRun.count,DymondDispatch::WorkItem.count]
    NevaehOs::Goals.tick!(plan.reload)
    assert_equal 'blocked',plan.reload.status
    assert_nil plan.steps.order(:position).last.nevaeh_agent_run_id
    assert_equal before,[NevaehAgentRun.count,DymondDispatch::WorkItem.count]
    assert NevaehWorkerReport.exists?(nevaeh_agent_run:source) # DB presence is no fallback.
  end

  def test_dependency_is_rechecked_after_queueing_and_before_dispatch
    plan,_=finish_first
    NevaehOs::Goals.tick!(plan.reload)
    run=plan.steps.order(:position).last.nevaeh_agent_run
    File.unlink(NevaehOs::ReportJournal.path(@actor))
    count=DymondDispatch::WorkItem.count
    NevaehOs::AgentWorkforce.execute!(run)
    assert_equal 'blocked',run.reload.status
    assert_nil run.nevaeh_os_action_id
    assert_equal count,DymondDispatch::WorkItem.count
  end

  def test_dependency_is_rechecked_when_the_dispatched_action_executes
    plan,_=finish_first
    NevaehOs::Goals.tick!(plan.reload)
    run=plan.steps.order(:position).last.nevaeh_agent_run
    NevaehOs::AgentWorkforce.execute!(run)
    action=run.reload.nevaeh_os_action
    File.unlink(NevaehOs::ReportJournal.path(@actor))
    NevaehOs::Resources.stub(:perform!,->(**) { flunk 'Dependent operation must not execute' }) do
      assert_raises(Gatekeeper::AuthorizationDenied) { execute(action) }
    end
    NevaehOs::Goals.tick!(plan.reload)
    assert_equal 'blocked',plan.reload.status
  end

  def test_foreign_unknown_and_tampered_references_never_resolve
    _,source=finish_first
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@other,dependency:dependency) }
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency.merge('report_ref'=>'unresolved:'+source.task_uuid)) }
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency.merge('task_id'=>SecureRandom.uuid)) }
    report=NevaehWorkerReport.find_by!(nevaeh_agent_run:source)
    changed=report.structured_result.deep_merge('output'=>{'action_id'=>999999})
    NevaehOs::ReportJournal.append!(@actor,changed)
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency) }
  end

  def test_changed_underlying_receipt_blocks_even_when_journal_and_report_agree
    _,source=finish_first
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    source.nevaeh_os_action.update!(result:{'records'=>[{'id'=>999999}]})
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency) }
  end

  def test_source_drift_blocks_resolving_an_otherwise_valid_report
    _,source=finish_first
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    tutorial=NevaehOs::Guide.method(:tutorial)
    NevaehOs::Guide.stub(:tutorial,lambda { |id,**args| tutorial.call(id,**args).merge(body:'Changed upstream manual') }) do
      assert_raises(ArgumentError) { NevaehOs::WorkerReports.resolve!(actor:@actor,dependency:dependency) }
    end
  end

  def test_failed_fsync_does_not_leave_a_readable_completed_report
    plan=read_plan
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start')
    NevaehOs::Goals.tick!(plan)
    run=plan.steps.first.nevaeh_agent_run
    NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
    original=File.method(:open)
    File.stub(:open,lambda { |*args,**kwargs,&block|
      original.call(*args,**kwargs) do |file|
        file.define_singleton_method(:fsync) { raise IOError,'Simulated journal fsync failure' }
        block.call(file)
      end
    }) { NevaehOs::Goals.tick!(plan.reload) }
    assert_equal 'blocked',plan.reload.status
    assert_nil plan.steps.order(:position).last.nevaeh_agent_run_id
    assert_empty NevaehOs::ReportJournal.read!(@actor)
  end

  def test_journal_only_uuid_collision_blocks_new_dispatch_without_overwriting
    _,source=finish_first
    uuid=SecureRandom.uuid
    report=NevaehWorkerReport.find_by!(nevaeh_agent_run:source).structured_result.merge('task_id'=>uuid)
    NevaehOs::ReportJournal.append!(@actor,report)
    bytes=File.binread(NevaehOs::ReportJournal.path(@actor))
    assert_raises(ArgumentError) { NevaehOs::AgentWorkforce.request!(worker:source.nevaeh_agent_worker,actor:@actor,key:SecureRandom.uuid,task_id:uuid) }
    assert_equal bytes,File.binread(NevaehOs::ReportJournal.path(@actor))
  end

  def test_schema_requires_explicit_reference_and_single_mapped_status
    _,source=finish_first
    value=NevaehWorkerReport.find_by!(nevaeh_agent_run:source).structured_result
    dependency=NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)
    [dependency.except('report_ref'),dependency.merge('status'=>'completed'),dependency.merge('runtime_status'=>'completed')].each do |bad|
      assert_raises(ArgumentError) { NevaehOs::ReportSchema.validate!(value.merge('dependencies'=>[bad])) }
    end
    assert_equal value,NevaehOs::ReportSchema.validate!(value.merge('dependencies'=>[]))
  end

  def test_legacy_journal_is_readable_but_cannot_supply_or_publish_uuid_dependencies
    _,source=finish_first
    value=NevaehWorkerReport.find_by!(nevaeh_agent_run:source).structured_result
    legacy=value.merge('schema_version'=>1,'task_id'=>"run-#{source.id}")
    File.write(NevaehOs::ReportJournal.path(@actor),JSON.generate(legacy)+"\n")
    assert_equal legacy,NevaehOs::ReportJournal.read!(@actor)[legacy['task_id']]
    assert_raises(ArgumentError) { NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source) }
    assert_raises(ArgumentError) { NevaehOs::ReportJournal.append!(@actor,legacy) }
    NevaehOs::ReportJournal.append!(@actor,value)
    assert_equal legacy,JSON.parse(File.readlines(NevaehOs::ReportJournal.path(@actor)).first)
    assert_equal 'accepted',NevaehOs::WorkerReports.dependency_for!(actor:@actor,run:source)['status']
  end

  def test_legacy_queued_goal_cannot_skip_missing_dependency_metadata
    plan,_=finish_first
    NevaehOs::Goals.tick!(plan.reload)
    run=plan.steps.order(:position).last.nevaeh_agent_run
    run.update!(snapshot:run.snapshot.except('report_dependencies'))
    File.unlink(NevaehOs::ReportJournal.path(@actor))
    NevaehOs::AgentWorkforce.execute!(run)
    assert_equal 'blocked',run.reload.status
    assert_nil run.nevaeh_os_action_id
  end

  def test_combined_steps_over_cap_are_rejected_before_any_dispatch
    rows=(7+6).times.map { |i| {'key'=>"step_#{i}",'agent'=>'nevaeh','command'=>'/read agents'} }
    before=[NevaehGoal.count,NevaehAgentRun.count,DymondDispatch::WorkItem.count]
    assert_raises(ArgumentError) { goal({'title'=>'Over cap','steps'=>rows}) }
    assert_equal before,[NevaehGoal.count,NevaehAgentRun.count,DymondDispatch::WorkItem.count]
  end
end
