# frozen_string_literal: true

# Isolated Sidekiq acceptance process using the installed application's queue
# and ticket database. Its queue is unique and never consumes production queues.
require "/var/www/lightekmcg-site/config/environment"
root = File.expand_path("..", __dir__)
ENV["NEVAEH_BACKLOG_ENABLED"] = "1"
{
  "NevaehIntelligences::GithubDevelopmentPlanV7a" => "app/services/nevaeh_intelligences/github_development_plan_v7a.rb",
  "NevaehIntelligences::TicketExecution" => "app/services/nevaeh_intelligences/ticket_execution.rb",
  "LightekMail::SendingPolicy" => "app/models/lightek_mail/sending_policy.rb",
  "Gatekeeper::LessonService" => "app/services/gatekeeper/lesson_service.rb"
}.each do |constant, path|
  constant.constantize
  load File.join(root, path)
end
# A candidate overlay must include its notification/KB dependencies. Keep
# notifications durably pending until release rather than delivering test mail
# or placing an undeployed job class on the production queue.
ENV["NEVAEH_ESCALATION_ENQUEUE"] = "0"
NevaehOrchestration::Escalation
load File.join(root, "app/services/nevaeh_orchestration/escalation.rb")
%w[structured_ticket structured_actions knowledge_procedures engineering_settings github_issue_client github_backlog central_reporting].each do |name|
  load File.join(root, "app/services/nevaeh_intelligences/#{name}.rb")
end
Dir[File.join(root, "app/services/nevaeh_intelligences/structured_workers/*.rb")].sort.each { |path| load path }
load File.join(root, "app/jobs/nevaeh_intelligences/knowledge_gap_notification_job.rb")
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

load File.join(root, "config/initializers/nevaeh_structured_worker.rb")
# This harness loads candidate hooks after Rails has already prepared. Normal
# application boot installs them through the initializer's to_prepare callback.
NevaehStructuredWorker.install!
