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
