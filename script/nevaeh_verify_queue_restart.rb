# frozen_string_literal: true

require "sidekiq/api"
require "tempfile"
require "securerandom"
require "rbconfig"
require_relative "nevaeh_backlog_worker_boot"
raise "Installed production runtime required" unless Rails.env.production?

# This existing smoke-test ticket has no executable work order. It exercises
# queue delivery and durable escalation without mutating a media or financial asset.
ticket = Marlon::Ticket.find(3)
raise "Controlled intake ticket changed; acceptance requires review" unless ticket.status != "resolved" &&
  ticket.title == "Seeing if this errors out or not." && ticket.extra_fields.to_h.dig("nevaeh", "work_item_id").blank?
queue_name = "nevaeh_acceptance_#{SecureRandom.hex(8)}"
queue = Sidekiq::Queue.new(queue_name)
log = Tempfile.new(["nevaeh-worker-acceptance-", ".log"])
worker_pid = nil

wait_for = lambda do |label, &condition|
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 90
  until condition.call
    raise "Timeout waiting for #{label}; inspect private worker log" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 0.2
  end
end
start_worker = lambda do
  Process.spawn(RbConfig.ruby, Gem.bin_path("sidekiq", "sidekiq"), "-e", "production",
    "-r", File.expand_path("nevaeh_backlog_worker_boot.rb", __dir__), "-q", queue_name, "-c", "1",
    out: log.path, err: [:child, :out], pgroup: true)
end
stop_worker = lambda do |pid|
  if pid
    begin
      Process.kill("TERM", pid)
      wait_for.call("worker exit") { !!Process.waitpid(pid, Process::WNOHANG) }
    rescue Errno::ESRCH, Errno::ECHILD
      # Already exited and reaped.
    end
  end
end

begin
  worker_pid = start_worker.call
  wait_for.call("first worker registration") do
    Sidekiq::ProcessSet.new.any? { |process| process["pid"].to_i == worker_pid && process.queues.include?(queue_name) }
  end
  Process.kill("TSTP", worker_pid)
  wait_for.call("worker quiet acknowledgement") do
    File.read(log.path).include?("Received TSTP, no longer accepting new work")
  end
  job = NevaehIntelligences::ProcessBacklogJob.set(queue: queue_name).perform_later(ticket_id: ticket.id)
  wait_for.call("durable queued delivery") { queue.size == 1 }
  original_payload = queue.first.item.deep_dup
  stop_worker.call(worker_pid)
  worker_pid = nil
  raise "Pending job lost when worker stopped" unless queue.size == 1
  worker_pid = start_worker.call
  wait_for.call("queued ticket processed after restart") do
    ticket.reload.extra_fields.to_h.dig("nevaeh_backlog", "job_receipts", job.job_id, "state") == "completed"
  end
  raise "Controlled ticket was incorrectly resolved" if ticket.reload.status == "resolved"
  count = ticket.events.where(action: "nevaeh_backlog_job_completed").where("detail LIKE ?", "%#{job.job_id}%").count
  raise "Missing durable completion evidence" unless count == 1
  Sidekiq::Client.push(original_payload.except("jid", "created_at", "enqueued_at"))
  wait_for.call("duplicate delivery consumed") { queue.size.zero? }
  # Stop waits for a currently running delivery to finish before checking evidence.
  stop_worker.call(worker_pid)
  worker_pid = nil
  count = ticket.events.where(action: "nevaeh_backlog_job_completed").where("detail LIKE ?", "%#{job.job_id}%").count
  raise "Duplicate delivery repeated completion" unless count == 1
  puts "NEVAEH_SIDEKIQ_RESTART_ACCEPTANCE=#{JSON.generate(queued_job_survived_restart: true,
    actual_ticket_processed: true, duplicate_delivery_suppressed: true, production_workers_restarted: false)}"
rescue StandardError => error
  ticket.log!(action: "nevaeh_queue_acceptance_failed", detail: JSON.generate(
    "error_class" => error.class.name, "error" => error.message,
    "private_worker_log_tail" => File.read(log.path).last(6000)))
  raise
ensure
  stop_worker.call(worker_pid)
  # Only this run's dedicated acceptance queue is touched.
  queue.clear
  log.close
end
