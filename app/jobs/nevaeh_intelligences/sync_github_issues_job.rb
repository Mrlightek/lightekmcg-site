# frozen_string_literal: true
module NevaehIntelligences
  class SyncGithubIssuesJob < ApplicationJob
    queue_as :default
    retry_on GithubIssueClient::Error, wait: :polynomially_longer, attempts: 5

    def perform(page: 1)
      return "disabled" unless EngineeringSettings.read["sync_enabled"]
      actor = User.find_by(id: EngineeringSettings.read["actor_id"])
      GithubBacklog.authorize_import!(actor: actor)
      batch = GithubIssueClient.new.issues(page: page)
      batch.fetch("records").each do |record|
        ticket = GithubBacklog.import!(record, actor: actor)
        ProcessBacklogJob.perform_later(ticket_id: ticket.id) unless ticket.status == "resolved"
      end
      self.class.perform_later(page: page + 1) if batch.fetch("more")
      {"count" => batch.fetch("records").size, "more" => batch.fetch("more")}
    end
  end
end
