# frozen_string_literal: true
# Authorized historical intake. Real GitHub records become canonical Marlon
# tickets and use the existing planning/escalation pipeline. No issue is closed
# or deployment performed by this import. Delivery jobs wait for the release.
require "json"
require "active_job/queue_adapters/test_adapter"
raise "Installed production runtime required" unless Rails.env.production?
root = File.expand_path("..", __dir__)
raise "Candidate must be separate from live application" if File.realpath(root) == File.realpath(Rails.root)
ActiveJob::Base.queue_adapter = :test
ENV["NEVAEH_BACKLOG_ENABLED"] = "0"
ENV["NEVAEH_ESCALATION_ENQUEUE"] = "0"
%w[work_order structured_ticket structured_actions knowledge_procedures engineering_settings github_issue_client github_backlog github_development_plan_v7a].each do |name|
  load File.join(root, "app/services/nevaeh_intelligences/#{name}.rb")
end
Dir[File.join(root, "app/services/nevaeh_intelligences/structured_workers/*.rb")].sort.each { |path| load path }
NevaehOrchestration::Escalation
load File.join(root, "app/services/nevaeh_orchestration/escalation.rb")
load File.join(root, "app/jobs/nevaeh_intelligences/knowledge_gap_notification_job.rb")
load File.join(root, "app/jobs/nevaeh_intelligences/sync_github_issues_job.rb")
load File.join(root, "app/services/nevaeh_intelligences/ticket_backlog.rb")
operator = User.where(role: "super_admin").order(:id).first || raise("No main application super administrator")
capability = NevaehIntelligences::StructuredTicket.registered!
capability.with_lock do
  metadata = capability.metadata.to_h.deep_stringify_keys
  metadata["github_engineering"] = metadata.fetch("github_engineering", {}).merge("sync_enabled" => true, "actor_id" => operator.id)
  capability.update!(metadata: metadata)
end
page = 1
loop do
  result = NevaehIntelligences::SyncGithubIssuesJob.new.perform(page: page)
  break unless result.fetch("more")
  page += 1
  raise "GitHub intake page bound exceeded; resume from the saved source records" if page > 100
end
ENV["NEVAEH_BACKLOG_ENABLED"] = "1"
results = NevaehIntelligences::GithubBacklog.relation.order(:id).map do |ticket|
  outcome = NevaehIntelligences::TicketBacklog.process!(ticket: ticket)
  fields = ticket.reload.extra_fields.to_h
  {"github_issue" => fields.dig("nevaeh_github", "number"), "ticket_id" => ticket.id, "ticket_number" => ticket.number,
    "outcome" => outcome, "blockers" => fields.dig("nevaeh_backlog", "blockers"), "assigned_team" => ticket.assigned_team,
    "kb_articles_consulted" => fields.dig("nevaeh_backlog", "knowledge_article_ids")}
end
raise "GitHub intake produced no real source tickets" if results.empty?
raise "Intake cannot claim unverified resolutions" if results.any? { |row| row["outcome"] == "resolved" && Marlon::Ticket.find(row["ticket_id"]).extra_fields.dig("nevaeh", "execution_status") != "verified" }
puts "NEVAEH_ACTUAL_GITHUB_BACKLOG=#{JSON.generate({"source_repository" => NevaehIntelligences::GithubBacklog::REPOSITORY,
  "tickets" => results, "github_issues_closed" => 0, "notification_delivery" => "pending_release_of_worker_code"})}"
