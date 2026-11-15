# frozen_string_literal: true
module NevaehOs
  module Presence
    module_function
    def for(actor)
      actions=NevaehOsAction.where(user:actor)
      projects=StudioProject.where(owner_id:actor.id)
      operations=StudioOperation.where(studio_project_id:projects.select(:id))
      publications=StudioPublication.where(studio_project_id:projects.select(:id))
      queued_actions=actions.where(status:'pending')
      queued_operations=operations.where(status:'pending')
      running=operations.where(status:'running').count+publications.where(status:'publishing').count
      queued=queued_actions.count+queued_operations.count
      waiting=operations.where(status:%w[awaiting_planning awaiting_approval awaiting_payment]).count
      delayed=queued_actions.where('updated_at < ?',10.minutes.ago).count+queued_operations.where('updated_at < ?',10.minutes.ago).count
      latest_action=actions.order(id: :desc).first
      latest_operation=operations.order(id: :desc).first
      latest=[latest_action,latest_operation,publications.order(id: :desc).first].compact.max_by(&:updated_at)
      latest_status=latest==latest_action && latest ? Receipts.for(latest)[:status] : latest&.status
      outstanding=latest_status=='dispatched'
      failed=%w[failed needs_review evidence_unavailable].include?(latest_status)
      review=latest_operation&.metadata&.dig('rehearsal_report','status')=='needs_attention'
      state,message=if running.positive?
        ['working',"#{running} #{running==1 ? 'task is' : 'tasks are'} running.#{queued.positive? ? " #{queued} queued." : ''}"]
      elsif delayed.positive?
        ['attention',"#{delayed} #{delayed==1 ? 'task is' : 'tasks are'} still queued after 10 minutes. Check the workers and receipts in the workspace."]
      elsif failed || review
        ['attention','A task needs attention. Open its receipt in the workspace.']
      elsif queued.positive?
        ['queued',"#{queued} #{queued==1 ? 'task is' : 'tasks are'} queued, waiting for a worker."]
      elsif outstanding
        ['waiting','A delegated task is awaiting a completion receipt. Open the workspace to check its progress.']
      elsif waiting.positive?
        ['waiting',"#{waiting} #{waiting==1 ? 'task needs' : 'tasks need'} planning, approval or payment before it can run."]
      elsif latest && latest.updated_at>1.day.ago && %w[completed published].include?(latest_status)
        ['idle','The latest task finished. Ready when you are.']
      else
        ['idle','Ready when you are.']
      end
      # Report records without mutating them or pretending a delay proves failure.
      items=queued_actions.order(:created_at).limit(3).map { |row| {type:'action',id:row.id,status:'queued',since:row.created_at} }
      items+=operations.where(status:%w[pending running]).order(:created_at).limit(3).map { |row| {type:'studio_operation',id:row.id,status:row.status=='pending' ? 'queued' : row.status,since:row.created_at} }
      {state:state,message:message,counts:{running:running,queued:queued,waiting:waiting,delayed:delayed,outstanding:outstanding ? 1 : 0},items:items,workspace_url:'/dashboard/nevaeh'}
    end
  end
end
