# frozen_string_literal: true

# Isolated Sidekiq acceptance process using the installed application's queue
# and ticket database. Its queue is unique and never consumes production queues.
require "/var/www/lightekmcg-site/config/environment"
root = File.expand_path("..", __dir__)
ENV["NEVAEH_BACKLOG_ENABLED"] = "1"
{
  "NevaehIntelligences::GithubDevelopmentPlanV7a" => "app/services/nevaeh_intelligences/github_development_plan_v7a.rb",
  "NevaehIntelligences::TicketExecution" => "app/services/nevaeh_intelligences/ticket_execution.rb",
  "Gatekeeper::LessonService" => "app/services/gatekeeper/lesson_service.rb"
}.each do |constant, path|
  constant.constantize
  load File.join(root, path)
end
load File.join(root, "app/services/nevaeh_intelligences/ticket_backlog.rb")
load File.join(root, "app/jobs/nevaeh_intelligences/process_backlog_job.rb")

# Candidate structured action handlers use the same dispatch worker and policy.
%w[structured_ticket structured_actions structured_repository structured_execution structured_ticket_worker].each do |name|
  load File.join(root, "app/services/nevaeh_intelligences/#{name}.rb")
end
{
  "NevaehIntelligences::WorkOrder" => "app/services/nevaeh_intelligences/work_order.rb",
  "Gatekeeper::AuthorizationService" => "app/services/gatekeeper/authorization_service.rb",
  "NevaehIntelligences::ExecutionGateV2f" => "app/services/nevaeh_intelligences/execution_gate_v2f.rb",
  "NevaehIntelligences::ReconcileTicketJob" => "app/jobs/nevaeh_intelligences/reconcile_ticket_job.rb"
}.each do |constant, path|
  constant.constantize
  load File.join(root, path)
end
