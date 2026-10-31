# frozen_string_literal: true

module NevaehIntelligences
  module StructuredActions
    module_function

    def site(actor, inputs)
      LightekSettings::WebsiteIdentity.sites_for(actor).find(inputs.fetch("site_id"))
    end

    def perform(action, inputs, actor:, ticket:)
      case action
      when "site.page.create"
        website = site(actor, inputs)
        page = website.pages.create!(title: inputs.fetch("title"), slug: inputs.fetch("slug"), published: false,
          position: website.pages.maximum(:position).to_i + 1)
        {"site_id" => website.id, "page_id" => page.id}
      when "site.section.add"
        website = site(actor, inputs)
        page = website.pages.find(inputs.fetch("page_id"))
        raise StructuredTicket::Invalid, "Use a draft page for automatic content changes" if page.published?
        definition = LightekDesign::Catalog.section_definition(inputs.fetch("kind")) || raise(StructuredTicket::Invalid, "Unknown registered section kind")
        allowed = definition.fetch("fields").map { |field| field.fetch("name") }
        raise StructuredTicket::Invalid, "Unknown section data fields" if (inputs.fetch("data").keys - allowed).any?
        section = page.sections.create!(kind: inputs.fetch("kind"), data: inputs.fetch("data"), position: page.sections.maximum(:position).to_i + 1)
        {"site_id" => website.id, "page_id" => page.id, "section_id" => section.id}
      when "studio.project.create"
        raise StructuredTicket::Invalid, "Studio project permission denied" unless Ability.new(actor).can?(:create, StudioProject)
        Studio::Workers::ProjectCreation.perform("create", inputs.merge("intent_key" => "production", "start_mode_key" => "blank")).deep_stringify_keys
      when "engineering.service.generate"
        StructuredRepository.generate!(ticket: ticket)
      else
        raise StructuredTicket::Invalid, "No executor for action"
      end
    end

    def verify!(action, inputs, output, actor:)
      case action
      when "site.page.create"
        page = site(actor, inputs).pages.find(output.fetch("page_id"))
        raise StructuredTicket::Invalid, "Page acceptance failed" unless page.title == inputs["title"] && page.slug == inputs["slug"] && !page.published?
      when "site.section.add"
        page = site(actor, inputs).pages.find(inputs.fetch("page_id"))
        section = page.sections.find(output.fetch("section_id"))
        raise StructuredTicket::Invalid, "Section acceptance failed" unless section.kind == inputs["kind"] && section.data.to_h.deep_stringify_keys == inputs["data"] && !page.published?
      when "studio.project.create"
        project = StudioProject.find(output.fetch("project_id"))
        production = Production.find_by!(id: output.fetch("production_id"), studio_project_id: project.id)
        StudioScene.find_by!(id: output.fetch("default_scene_id"), studio_project_id: project.id, production_id: production.id)
        raise StructuredTicket::Invalid, "Studio acceptance failed" unless project.name == inputs["name"]
      when "engineering.service.generate"
        StructuredRepository.verify!(output)
      else
        raise StructuredTicket::Invalid, "No verifier for action"
      end
      true
    end
  end
end
