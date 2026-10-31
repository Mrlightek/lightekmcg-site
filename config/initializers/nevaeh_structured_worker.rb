# frozen_string_literal: true

# Keep registered structured work on its configured queue even on dispatch
# versions whose enqueue helper defaults to the application's default queue.
module NevaehStructuredWorker
  def perform(work_item_id)
    item = DymondDispatch::WorkItem.find_by(id: work_item_id)
    return super unless item&.kind == NevaehIntelligences::StructuredTicket::CAPABILITY
    claimed = DymondDispatch::WorkItem.where(id: item.id, status: "queued").update_all([
      "status = ?, worker_id = ?, started_at = ?, attempts = COALESCE(attempts, 0) + 1",
      "working", send(:worker_id), Time.current
    ])
    return unless claimed == 1
    item.reload
    begin
      NevaehIntelligences::StructuredExecution.authorize_item!(item)
      result = NevaehIntelligences::StructuredTicketWorker.perform(*item.args)
      item.mark_done!(result)
    rescue StandardError => error
      item.mark_failed!("#{error.class}: #{error.message}")
    end
    # The originating ticket is reconciled by the existing ticket job. Do not
    # create a second escalation ticket through generic failure dispositions.
    NevaehIntelligences::ReconcileTicketJob.set(queue: item.queue).perform_later(item.subject_id)
    item
  end
end

def NevaehStructuredWorker.install!
  worker = DymondDispatch::PerformWorkItemJob
  unless worker.ancestors.include?(NevaehStructuredWorker)
    worker.before_enqueue do |job|
      item = DymondDispatch::WorkItem.find_by(id: job.arguments.first)
      if item&.kind == NevaehIntelligences::StructuredTicket::CAPABILITY
        capability = NevaehCapability.find_by!(slug: item.kind)
        job.queue_name = capability.queue
        item.update!(queue: capability.queue) unless item.queue == capability.queue
      end
    end
    worker.prepend(NevaehStructuredWorker)
  end
end

# Engine job autoloading is ready during preparation, not while application
# initializers are first evaluated (including rails db:migrate).
Rails.application.config.to_prepare { NevaehStructuredWorker.install! }
