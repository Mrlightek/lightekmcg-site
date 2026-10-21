# frozen_string_literal: true
# Run with RAILS_ENV=development REDIS_URL=redis://127.0.0.1:6379/1 bin/rails runner script/nevaeh_ticket_concurrency_proof.rb
require 'securerandom'
require 'json'
abort 'STOP: development only' unless Rails.env.development?
abort 'STOP: Sidekiq adapter required' unless ActiveJob::Base.queue_adapter.class.name.include?('Sidekiq')
actor = User.where(role: %w[admin super_admin]).first
abort 'STOP: no administrator in development database' unless actor
registry = NevaehIntelligence.available.find_by(intent_key: 'studio.project.create')
abort 'STOP: Studio intelligence is not published/enabled' unless registry
abort 'STOP: wrong handler' unless registry.nevaeh_capability.handler == 'Studio::Workers::ProjectCreation'
require 'sidekiq/api'
abort 'STOP: no live Sidekiq process with default queue' unless Sidekiq::ProcessSet.new.any? { |p| Array(p['queues']).include?('default') }
name = "[NEVAEH CONCURRENCY] #{Time.now.utc.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}"
order = NevaehIntelligences::WorkOrder.template.merge(
  'objective' => 'Create exactly one Studio project from competing dispatch requests',
  'inputs' => {'name' => name, 'description' => 'development concurrency acceptance proof', 'intent_key' => 'production', 'start_mode_key' => 'blank'},
  'acceptance_criteria' => ['Exactly one work item dispatched', 'Studio project, production and scene persisted'],
  'execution_policy' => {'environment' => 'development', 'approval' => 'gatekeeper'})
ticket = Marlon::Ticket.create!(title: name, description: 'Concurrent ticket execution test',
  category: Marlon::TicketCategories.ids.first, priority: 'medium', urgency: 5, status: 'open', submitted_by: actor)
NevaehIntelligences::WorkOrder.attach!(ticket: ticket, attributes: order)
puts "CONCURRENCY_TICKET: #{ticket.id} #{ticket.number}"
ready = Queue.new
start = Queue.new
results = Queue.new
threads = 2.times.map do |i|
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      ready << i
      start.pop
      begin
        local_ticket = Marlon::Ticket.find(ticket.id)
        receipt = NevaehIntelligences::WorkOrder.dispatch!(ticket: local_ticket, actor: actor)
        results << {'thread' => i, 'result' => 'dispatched', 'work_item_id' => receipt.fetch('work_item_id')}
      rescue NevaehIntelligences::WorkOrder::Invalid, NevaehIntelligences::TicketExecution::InvalidTicket => e
        results << {'thread' => i, 'result' => 'rejected', 'reason' => e.message}
      rescue => e
        results << {'thread' => i, 'result' => 'unexpected_error', 'class' => e.class.name, 'message' => e.message}
      end
    end
  end
end
2.times { ready.pop }
2.times { start << true }
threads.each(&:join)
outcomes = 2.times.map { results.pop }
puts "CONCURRENCY_OUTCOMES: #{JSON.generate(outcomes)}"
abort 'PROOF_FAIL: expected exactly one dispatched and one rejected' unless outcomes.count { |o| o['result'] == 'dispatched' } == 1 && outcomes.count { |o| o['result'] == 'rejected' } == 1
ticket.reload
state = ticket.extra_fields.to_h.fetch('nevaeh', {})
work_id = state['work_item_id']
abort 'PROOF_FAIL: dispatch linkage absent' unless work_id && outcomes.find { |o| o['result'] == 'dispatched' }['work_item_id'].to_s == work_id.to_s
abort 'PROOF_FAIL: duplicate dispatch events' unless ticket.events.where(action: 'nevaeh_dispatched').count == 1
# Background processing and delayed reconciliation may take time; never force a ticket to resolved here.
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
loop do
  ticket.reload
  break if ticket.status == 'resolved'
  break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  sleep 2
end
item = DymondDispatch::WorkItem.find(work_id)
abort "PROOF_INCOMPLETE: ticket=#{ticket.id} status=#{ticket.status} work_item=#{work_id} status=#{item.status}; inspect worker/reconciliation" unless ticket.status == 'resolved' && item.status == 'done'
project = StudioProject.find_by(name: name)
abort 'PROOF_FAIL: expected single project' unless StudioProject.where(name: name).count == 1 && project
abort 'PROOF_FAIL: production/scene missing' unless Production.where(studio_project_id: project.id).exists? && StudioScene.where(studio_project_id: project.id).exists?
puts "CONCURRENCY_PROOF_PASS: #{JSON.generate(ticket_id: ticket.id, number: ticket.number, work_item_id: work_id, project_id: project.id, status: ticket.status, outcomes: outcomes)}"
