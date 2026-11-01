# frozen_string_literal: true
module NevaehIntelligences
  module StructuredActions
    module_function

    def site(actor, inputs)
      LightekSettings::WebsiteIdentity.sites_for(actor).find(inputs.fetch("site_id"))
    end

    def worker_for(action)
      # Only application-registered workers can execute. KB prose cannot name an
      # arbitrary constant, evaluate source, or introduce a shell command.
      case action
      when "site.page.create" then StructuredWorkers::CreatePage
      when "site.section.add" then StructuredWorkers::AddSection
      when "studio.project.create" then StructuredWorkers::CreateStudioProject
      when "engineering.service.generate" then StructuredWorkers::GenerateMetadataService
      else raise StructuredTicket::Invalid, "No registered structured worker for #{action}"
      end
    end

    def perform(action, inputs, actor:, ticket:)
      worker_for(action).perform(inputs, actor: actor, ticket: ticket)
    end

    def verify!(action, inputs, output, actor:, ticket: nil)
      worker_for(action).verify!(inputs, output, actor: actor)
    end
  end
end
