require_relative 'nevaeh_worker_report_checks'
class NevaehReportingConventionChecks < NevaehWorkerReportChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)

  def test_worker_reopens_exact_assigned_page_and_rejects_different_instruction_or_changed_source
    run,_=task
    stamp=run.snapshot.fetch('documentation_contract')
    assert_equal 'docs/nevaeh/tutorials/platform.md',stamp['path']
    assert_equal stamp['sha256'],run.snapshot.dig('documentation_read','sha256')
    refute_nil run.snapshot.dig('documentation_read','read_at')
    reads=[];original=File.method(:read)
    File.stub(:read,lambda { |path,*args,**kw| reads<<path.to_s;original.call(path,*args,**kw) }) do
      NevaehOs::DocumentationWorkers.read!(actor:@actor,command:run.snapshot)
    end
    assert reads.any? { |p| p.end_with?(stamp['path']) }
    assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.read!(actor:@actor,command:run.snapshot.merge('intent'=>'messages.people')) }
    worker=run.nevaeh_agent_worker
    rewritten=worker.command.deep_dup
    rewritten['documentation_contract']['path']='docs/nevaeh/tutorials/commands.md'
    assert_raises(ActiveRecord::RecordInvalid) { worker.update!(command:rewritten) }
    tutorial=NevaehOs::Guide.method(:tutorial)
    NevaehOs::Guide.stub(:tutorial,lambda { |id,**args| tutorial.call(id,**args).merge(body:'Changed page') }) do
      assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.read!(actor:@actor,command:run.snapshot) }
    end
  end

  def test_fixed_json_schema_rejects_free_text_missing_fields_extra_fields_and_invalid_status
    run,item=task;item.update!(status:'done');value=report_for(run).structured_result
    assert_equal value,NevaehOs::ReportSchema.validate!(value)
    ["done",value.except('dependencies'),value.merge('output'=>'all done'),value.merge('extra'=>'not in schema'),value.merge('status'=>'probably finished'),value.merge('task_id'=>"run-1\n"),value.deep_merge('file_ownership'=>{'write_files'=>['../outside']})].each do |bad|
      assert_raises(ArgumentError) { NevaehOs::ReportSchema.validate!(bad) }
    end
    assert_equal "run-#{run.id}",value['task_id']
    assert_equal 'receipt_reference',value.dig('output','kind')
    assert_equal [],value['dependencies']
    assert_equal [],value.dig('file_ownership','write_files')
    assert_equal 'manager',value.dig('file_ownership','report_writer')
  end

  def test_manager_writes_and_reads_validated_shared_json_not_plain_text_or_duplicate_events
    run,item=task;first=report_for(run)
    journal=NevaehOs::ReportJournal.path(@actor)
    lines=File.readlines(journal).size
    report_for(run)
    assert_equal lines,File.readlines(journal).size
    assert_equal 'pending',NevaehOs::WorkerReports.journal_result!(first)['status']
    item.update!(status:'done');report=report_for(run)
    assert_equal lines+1,File.readlines(journal).size
    assert_equal 'completed',NevaehOs::WorkerReports.journal_result!(report)['status']
    assert_equal report.structured_result,NevaehOs::WorkerReports.row(report)[:structured_report]
    assert_equal 0600,File.stat(journal).mode & 0777
    assert_empty NevaehOs::ReportJournal.read!(@other)
    assert_raises(ArgumentError) { NevaehOs::ReportJournal.append!(@other,report.structured_result) }
    File.write(journal,"unstructured answer\n")
    assert_raises(ArgumentError) { NevaehOs::ReportJournal.read!(@actor) }
    assert_raises(ArgumentError) { experience(run) }
  end

  def test_parallel_manager_appends_do_not_interleave_or_lose_worker_results
    run,item=task;item.update!(status:'done');template=report_for(run).structured_result
    threads=10.times.map do |i|
      Thread.new { NevaehOs::ReportJournal.append!(@actor,template.merge('task_id'=>"run-#{run.id+100+i}")) }
    end
    threads.each(&:value)
    latest=NevaehOs::ReportJournal.read!(@actor)
    assert_equal 11,latest.size
    File.foreach(NevaehOs::ReportJournal.path(@actor)) { |line| assert NevaehOs::ReportSchema.validate!(JSON.parse(line)) }
  end

  def worker_with_files(files)
    agent=NevaehOs::Agents.resolve!('sage',@actor)
    worker=NevaehAgentWorker.create!(user:@actor,nevaeh_os_agent:agent,name:'Document worker',command:{'kind'=>'resource','operation'=>'read','resource'=>'agents'})
    NevaehOs::DocumentationWorkers.assign_files!(actor:@actor,worker:worker,files:files)
    run=NevaehOs::AgentWorkforce.request!(actor:@actor,worker:worker,key:SecureRandom.uuid)
    [worker,run]
  end
  def test_exact_file_ownership_blocks_parallel_conflicts_undeclared_paths_and_symlinks
    Dir.mktmpdir('nevaeh-owned-files-') do |root|
      NevaehOs::DocumentationWorkers.stub(:workspace_root,Pathname.new(root)) do
        worker,run=worker_with_files(['scripts/intro.txt'])
        result=NevaehOs::DocumentationWorkers.write!(run:run,path:'scripts/intro.txt',content:'Opening scene')
        assert_equal 'scripts/intro.txt',result[:path]
        assert_equal 'Opening scene',File.read(File.join(root,"account-#{@actor.id}/scripts/intro.txt"))
        assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.write!(run:run,path:'scripts/unowned.txt',content:'no') }
        assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.write!(run:run,path:'../reports.jsonl',content:'no') }
        _,other=worker_with_files(['scripts/intro.txt'])
        assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.write!(run:other,path:'scripts/intro.txt',content:'conflict') }
        assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.assign_files!(actor:@actor,worker:worker,files:['changed.txt']) }
        other.update!(status:'blocked')
        assert NevaehOs::DocumentationWorkers.write!(run:run,path:'scripts/intro.txt',content:'Revised')
        _,linked=worker_with_files(['linked/new/file.txt'])
        Dir.mktmpdir('nevaeh-outside-') do |outside|
          File.symlink(outside,File.join(root,"account-#{@actor.id}/linked"))
          assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.write!(run:linked,path:'linked/new/file.txt',content:'no') }
          refute Dir.exist?(File.join(outside,'new'))
        end
      end
    end
  end

  def test_goal_report_contains_actual_prior_task_dependencies
    plan=NevaehOs::Goals.create!(actor:@actor,request_key:SecureRandom.uuid,values:{'title'=>'Two workers','steps'=>[
      {'key'=>'first','agent'=>'nevaeh','command'=>'/create agents {"name":"Report dependency"}'},
      {'key'=>'second','agent'=>'nevaeh','command'=>'/read agents'}]})
    NevaehOs::Goals.control!(goal:plan,actor:@actor,operation:'start')
    runs=[]
    2.times do
      NevaehOs::Goals.tick!(plan.reload)
      run=plan.steps.where(status:'running').first.nevaeh_agent_run;runs<<run
      NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
      NevaehOs::Goals.tick!(plan.reload)
    end
    report=report_for(runs.last)
    assert_equal [{'task_id'=>"run-#{runs.first.id}",'status'=>'completed'}],report.structured_result['dependencies']
  end

  def test_one_page_sme_answers_with_fresh_source_excerpts_and_structured_manager_report
    chat=NevaehOs::Conversation.new(actor:@actor)
    result=chat.ask(text:'/page agents How do I delegate a task?',request_key:SecureRandom.uuid,mode:'operate')
    outer=NevaehOsAction.find(result.fetch('action_id'));execute(outer)
    run=NevaehAgentRun.find(outer.reload.result.fetch('agent_run_id'))
    agent=run.nevaeh_agent_worker.nevaeh_os_agent
    assert_equal 'page_agents',agent.system_key
    scoped=chat.ask(text:'How do I delegate?',agent:agent.id.to_s,page_context:@context,request_key:SecureRandom.uuid)
    assert_equal 'agents',NevaehOsAction.find(scoped['action_id']).command['topic']
    assert_raises(ArgumentError) { chat.ask(text:'/page studio show assets',agent:agent.id.to_s,request_key:SecureRandom.uuid) }
    assert_raises(ArgumentError) { chat.ask(text:'messages.list',agent:agent.id.to_s,request_key:SecureRandom.uuid,page_context:@context) }
    assert_equal 'docs/nevaeh/tutorials/agents.md',run.snapshot.dig('documentation_contract','path')
    NevaehOs::AgentWorkforce.execute!(run);execute(run.reload.nevaeh_os_action)
    output=run.nevaeh_os_action.reload.result
    assert output['matches'].any?
    source=File.readlines(Rails.root.join(output.dig('documentation','path')))
    output['matches'].each { |m| assert_equal source[m['line']-1,3].join.first(1200),m['text'] }
    report=report_for(run)
    assert_equal 'completed',report.structured_result['status']
    assert_equal "run-#{run.id}",NevaehOs::WorkerReports.journal_result!(report)['task_id']
    foreign=run.snapshot.merge('topic'=>'studio')
    assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.bind!(actor:@actor,command:foreign) }
    assert_raises(ArgumentError) { NevaehOs::DocumentationWorkers.delegate_question!(actor:@other,topic:'console',query:'show schema',key:SecureRandom.uuid) }
    empty=run.snapshot.except('documentation_contract','documentation_read').merge('query'=>'zyxwvuunfindable')
    empty=NevaehOs::DocumentationWorkers.bind!(actor:@actor,command:empty)
    assert NevaehOs::DocumentationWorkers.answer!(actor:@actor,command:empty)['needs_manager']
  end
end
