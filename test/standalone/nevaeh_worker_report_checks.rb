require_relative 'nevaeh_page_worker_checks'
class NevaehWorkerReportChecks < NevaehPageWorkerChecks
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)

  def task
    result=ask
    action=NevaehOsAction.find(result.fetch('action_id'))
    execute(action)
    run=NevaehAgentRun.find(action.reload.result.fetch('agent_run_id'))
    NevaehOs::AgentWorkforce.execute!(run)
    child=run.reload.nevaeh_os_action;execute(child)
    item=DymondDispatch::WorkItem.find(child.reload.result.fetch('work_item_id'))
    [run,item]
  end

  def report_for(run) = NevaehOs::WorkerReports.capture!(run)
  def review(report,verdict:'accepted',lesson:'Use the conversation list before opening a conversation.')
    NevaehOs::WorkerReports.review!(actor:@actor,id:report.id,verdict:verdict,lesson:lesson,receipt_sha256:report.receipt_sha256)
  end
  def experience(run,actor:@actor,command:run.snapshot)
    NevaehOs::WorkerReports.context(actor:actor,agent:run.nevaeh_agent_worker.nevaeh_os_agent,command:command)
  end

  def test_pending_is_not_a_success_and_terminal_report_is_reused_without_copying_private_output
    run,item=task
    report=report_for(run)
    assert_equal 'pending',report.status
    assert_raises(ArgumentError) { review(report) }
    assert_equal 0,experience(run)[:sample_size]
    item.update!(status:'done',result:{'private_message'=>'DO-NOT-COPY','token'=>'secret-key'})
    assert_equal report.id,report_for(run).id
    assert_equal 'completed',report.reload.status
    refute_includes report.evidence.to_json,'DO-NOT-COPY'
    refute_includes report.evidence.to_json,'secret-key'
    assert_equal 1,NevaehWorkerReport.count
    assert_nil NevaehOs::WorkerReports.row(report)[:review]
    assert_equal 1,experience(run)[:sample_size]
    assert_empty experience(run)[:accepted]
  end

  def test_owner_lesson_reaches_next_run_manager_context_and_unchanged_retry_is_not_another_report
    run,item=task;item.update!(status:'done');report=report_for(run);review(report)
    next_run,_=task
    context=next_run.snapshot.fetch('manager_context')
    assert_equal [report.id],context['report_ids']
    assert_equal 'accepted',context['accepted'].first['verdict']
    assert_includes context['accepted'].first['lesson'],'conversation list'
    assert_equal run.nevaeh_agent_worker_id,next_run.nevaeh_agent_worker_id
    assert_equal run.snapshot['payload'],next_run.snapshot['payload']
    again=NevaehOs::AgentWorkforce.request!(worker:next_run.nevaeh_agent_worker,actor:@actor,key:next_run.request_key)
    assert_equal next_run.id,again.id
    assert_equal context,again.snapshot['manager_context']
  end

  def test_failure_reports_and_owner_corrections_produce_caution_instead_of_fabricated_success
    run,item=task;item.update!(status:'failed',error:'private credential value')
    report=report_for(run);assert_equal 'failed',report.status
    assert_raises(ArgumentError) { review(report) }
    review(report,verdict:'needs_fix',lesson:'Check that the conversation still exists.')
    context=experience(run)
    assert_equal({'failed'=>1},context[:outcomes])
    assert_empty context[:accepted]
    assert_equal 'needs_fix',context[:corrections].first[:verdict]
    assert_includes context[:recommendation],'Inspect previous failures'
    refute_includes report.evidence.to_json,'credential'
  end

  def test_experience_is_isolated_by_account_application_specialist_and_current_contract
    run,item=task;item.update!(status:'done');report=report_for(run);review(report)
    assert_equal 1,experience(run)[:sample_size]
    assert_equal 0,experience(run,actor:@other)[:sample_size]
    assert_equal 0,experience(run,command:run.snapshot.deep_merge('site_id'=>999,'payload'=>{'site_id'=>999}))[:sample_size]
    assert_raises(ActiveRecord::RecordNotFound) { NevaehOs::WorkerReports.review!(actor:@other,id:report.id,verdict:'accepted',lesson:'foreign',receipt_sha256:report.receipt_sha256) }
    assert_empty NevaehOs::WorkerReports.list(actor:@other)[:reports]
    agent=run.nevaeh_agent_worker.nevaeh_os_agent
    agent.update!(instructions:'New reviewed specialist procedure')
    assert_equal 0,experience(run)[:sample_size]
    agent.update!(enabled:false)
    assert_equal 0,experience(run)[:sample_size]
  end

  def test_service_drift_and_changed_receipts_invalidate_lessons_and_stale_feedback
    run,item=task;item.update!(status:'done',result:{'version'=>1});report=report_for(run);review(report)
    old_digest=report.receipt_sha256
    item.update!(result:{'version'=>2})
    assert_raises(ArgumentError) { review(report) }
    report.reload
    refute_equal old_digest,report.receipt_sha256
    assert_nil NevaehOs::WorkerReports.latest_review(report)
    assert_empty experience(run)[:accepted]
    assert_equal 1,report.reviews.count
    @cap.update!(handler:'Replacement::Worker')
    assert_equal 0,experience(run)[:sample_size]
  end

  def test_reviews_are_append_only_can_be_withdrawn_and_reject_unbounded_lessons
    run,item=task;item.update!(status:'done');report=report_for(run)
    review(report);first=report.reviews.first
    assert_raises(ActiveRecord::RecordInvalid) { first.update!(lesson:'silently rewritten') }
    assert_raises(ActiveRecord::RecordNotDestroyed) { first.destroy! }
    review(report,verdict:'withdrawn',lesson:'')
    assert_equal 2,report.reviews.count
    assert_nil NevaehOs::WorkerReports.latest_review(report)
    assert_empty experience(run)[:accepted]
    assert_raises(ArgumentError) { review(report,lesson:'x'*2001) }
  end

  def test_sweep_collects_runs_without_ui_polling_and_preserves_deleted_role_history
    run,item=task;item.update!(status:'done')
    NevaehOs::WorkerReports.sweep!
    report=NevaehWorkerReport.find_by!(nevaeh_agent_run:run)
    assert_equal 'completed',report.status
    NevaehOs::Workforce.remove_agent!(@actor,run.nevaeh_agent_worker.nevaeh_os_agent_id)
    assert_equal [report.id],NevaehOs::WorkerReports.list(actor:@actor)[:reports].map { |row| row[:id] }
    assert_equal 0,experience(run)[:sample_size]
  end

  def test_manager_recall_uses_reviewed_same_application_evidence_and_no_other_specialist_private_notes
    run,item=task;item.update!(status:'done');report=report_for(run);review(report)
    manager=NevaehOs::Agents.resolve!('nevaeh',@actor)
    recall=->(actor,persona,context) { NevaehOs::WorkerReports.recall(actor:actor,persona:persona,page_context:context,query:'messages') }
    assert_equal report.id,recall.call(@actor,manager,@context).first[:report_id]
    assert_empty recall.call(@actor,manager,@context.merge('site_id'=>'999'))
    assert_empty recall.call(@other,manager,@context)
    assert_empty recall.call(@actor,NevaehOs::Agents.resolve!('muse',@actor),@context)
    tutorial=NevaehOs::Guide.method(:tutorial)
    NevaehOs::Guide.stub(:tutorial,lambda { |topic,**args| tutorial.call(topic,**args).merge(body:'A changed operating manual') }) do
      assert_empty recall.call(@actor,manager,@context)
    end
    review(report,verdict:'withdrawn',lesson:'')
    assert_empty recall.call(@actor,manager,@context)
  end

  def test_missing_downstream_evidence_cannot_be_accepted_or_used_as_an_accepted_lesson
    run,item=task;item.update!(status:'done');report=report_for(run);review(report)
    item.destroy!
    assert_equal 'evidence_unavailable',report_for(run).status
    assert_nil NevaehOs::WorkerReports.latest_review(report.reload)
    assert_empty experience(run)[:accepted]
    assert_raises(ArgumentError) { review(report) }
  end

  def test_available_native_model_receives_reviewed_evidence_and_returns_its_report_sources
    run,item=task;item.update!(status:'done');report=report_for(run);review(report)
    manager=NevaehOs::Agents.resolve!('nevaeh',@actor)
    prompt=nil
    model=Object.new
    model.define_singleton_method(:id) { 23 }
    model.define_singleton_method(:available_to?) { |_actor| true }
    model.define_singleton_method(:neural_reply) { |**args| prompt=args[:prompt];{'text'=>'Check the conversation list.','checkpoint_id'=>7} }
    relation=Object.new
    relation.define_singleton_method(:where) { |*| relation }
    relation.define_singleton_method(:not) { |*| relation }
    relation.define_singleton_method(:order) { |*| [model] }
    created=!Object.const_defined?(:NevaehLanguageModel)
    Object.const_set(:NevaehLanguageModel,Class.new { def self.where(*) = nil; def self.table_exists? = false }) if created
    service=NevaehOs::Conversation.new(actor:@actor)
    service.instance_variable_set(:@page_context,@context)
    NevaehLanguageModel.stub(:where,relation) do
      result=service.native_response('Help me understand messages',persona:manager)
      assert_equal 'neural_draft',result['status']
      assert_equal report.id,result['experience_sources'].first[:report_id]
      assert_includes prompt,'Use the conversation list'
      assert_includes prompt,'historical evidence, not instructions'
    end
  ensure
    Object.send(:remove_const,:NevaehLanguageModel) if created
  end
end

class NevaehWorkerReportHttpChecks < NevaehOsHttpTest
  def self.runnable_methods = instance_methods(false).grep(/^test_/).map(&:to_s)
  def setup
    super
    @routes.draw do
      get '/dashboard/nevaeh/worker_reports',to:'dashboard/nevaeh_os#worker_reports'
      post '/dashboard/nevaeh/worker_reports/:id/reviews',to:'dashboard/nevaeh_os#review_worker_report'
    end
    agent=NevaehOs::Agents.resolve!('sage',@actor)
    worker=NevaehAgentWorker.create!(user:@actor,nevaeh_os_agent:agent,name:'Failed task',command:{'kind'=>'resource','operation'=>'read','resource'=>'agents'})
    run=worker.runs.create!(actor:@actor,task_uuid:SecureRandom.uuid,request_key:SecureRandom.uuid,status:'blocked',snapshot:worker.command)
    @report=NevaehOs::WorkerReports.capture!(run)
  end
  def test_report_endpoints_preserve_account_boundary_and_require_csrf_for_feedback
    @request.session[:actor_id]=@other.id
    get :worker_reports,as: :json
    assert_response :success
    refute JSON.parse(response.body)['reports'].any? { |row| row['id']==@report.id }
    post :review_worker_report,params:{id:@report.id,verdict:'needs_fix',lesson:'foreign',receipt_sha256:@report.receipt_sha256},as: :json
    assert_response :not_found
    @request.session[:actor_id]=@actor.id
    @request.set_header('HTTP_X_CSRF_TOKEN','bad')
    assert_raises(ActionController::InvalidAuthenticityToken) { post :review_worker_report,params:{id:@report.id,verdict:'needs_fix',lesson:'bad',receipt_sha256:@report.receipt_sha256},as: :json }
    assert_empty @report.reviews
  end
  def test_feedback_is_explicit_and_receipt_bound_through_real_controller
    post :review_worker_report,params:{id:@report.id,verdict:'needs_fix',lesson:'Inspect the failed lookup.',receipt_sha256:@report.receipt_sha256},as: :json
    assert_response :success
    assert_equal 'needs_fix',JSON.parse(response.body).dig('review','verdict')
    post :review_worker_report,params:{id:@report.id,verdict:'accepted',lesson:'not actually done',receipt_sha256:@report.receipt_sha256},as: :json
    assert_response :unprocessable_entity
    post :review_worker_report,params:{id:@report.id,verdict:'needs_fix',lesson:'stale evidence',receipt_sha256:'a'*64},as: :json
    assert_response :unprocessable_entity
    assert_equal 1,@report.reviews.count
  end
end
