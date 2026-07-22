#!/bin/bash
set -e
cd ~/Desktop/Development/dymond_dispatch

cat > app/jobs/dymond_dispatch/perform_work_item_job.rb << 'EOF'
# frozen_string_literal: true
module DymondDispatch
  # The agent taking the call. Accepts TWO handler contracts:
  #   1. a plain class responding to .perform(*args) -> result
  #   2. an ActiveJob subclass -> executed inline via perform_now
  # (2) lets existing ActiveJob classes — e.g. prayer-appointed jobs — be
  # dispatched without rewriting them. One worker, one WorkItem, one status.
  #
  # ACCOUNTABILITY: any failure here auto-opens a real Marlon::Ticket — not
  # opt-in per WorkItem, blanket policy. A failed charge, a stuck deploy, a
  # broken order reconciliation — none of it should sit silent in a table
  # nobody's watching. If this turns out noisy for some kinds, add a
  # suppression mechanism later; right now every failure gets a human ticket.
  class PerformWorkItemJob < ActiveJob::Base
    queue_as :default

    def perform(work_item_id)
      wi = WorkItem.find_by(id: work_item_id)
      return unless wi&.queued?

      wi.mark_working!(worker_id)
      begin
        result = invoke(wi)
        wi.mark_done!(result.is_a?(Hash) ? result : { value: result.to_s })
      rescue StandardError => e
        wi.mark_failed!("#{e.class}: #{e.message}")
        auto_escalate!(wi, e)
      end

      Dispositions.fire!(wi)
      wi
    end

    private

    def invoke(wi)
      klass = wi.handler.to_s.safe_constantize
      raise "unknown handler #{wi.handler}" if klass.nil?

      args = Array(wi.args)
      if klass.respond_to?(:perform)
        klass.perform(*args)
      elsif defined?(ActiveJob::Base) && klass < ActiveJob::Base
        klass.perform_now(*args)
      else
        raise "handler #{wi.handler} must respond to .perform or be an ActiveJob"
      end
    end

    def auto_escalate!(wi, error)
      return unless defined?(Marlon::Ticket)

      ticket = Marlon::Ticket.create!(
        category: "technical",
        title: "WorkItem failed — #{wi.kind} (##{wi.id})",
        description: "Handler: #{wi.handler}\nQueue: #{wi.queue}\nError: #{error.class}: #{error.message}",
        priority: "high",
        urgency: 7,
        related: wi.subject
      )
      ticket.log!(action: "Auto-escalated from failed WorkItem ##{wi.id}")
    rescue StandardError => e
      # Never let escalation itself take down the job — just log it.
      Rails.logger.error "[dispatch] auto-escalation failed for WorkItem ##{wi.id}: #{e.message}"
    end

    def worker_id
      @worker_id ||= begin
        require "socket"
        "#{Socket.gethostname}:#{Process.pid}:#{Thread.current.object_id}"
      rescue StandardError
        "worker:#{Process.pid}"
      end
    end
  end
end
EOF

echo "Done. Next:"
echo "  git add -A"
echo "  git commit -m 'Auto-escalate failed WorkItems to real tickets — blanket policy'"
echo "  git push"
echo ""
echo "  cd ~/Desktop/Development/lightekmcg-site"
echo "  bundle update dymond_dispatch"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
