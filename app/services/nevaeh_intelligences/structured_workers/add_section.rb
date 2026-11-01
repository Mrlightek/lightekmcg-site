# frozen_string_literal: true
module NevaehIntelligences
  module StructuredWorkers
    class AddSection
      def self.perform(inputs, actor:, ticket:)
        website = StructuredActions.site(actor, inputs)
        page = website.pages.find(inputs.fetch("page_id"))
        raise StructuredTicket::Invalid, "Use a draft page for automatic content changes" if page.published?
        definition = LightekDesign::Catalog.section_definition(inputs.fetch("kind")) || raise(StructuredTicket::Invalid, "Unknown registered section kind")
        allowed = definition.fetch("fields").map { |field| field.fetch("name") }
        raise StructuredTicket::Invalid, "Unknown section data fields" if (inputs.fetch("data").keys - allowed).any?
        section = page.sections.create!(kind: inputs.fetch("kind"), data: inputs.fetch("data"), position: page.sections.maximum(:position).to_i + 1)
        {"site_id" => website.id, "page_id" => page.id, "section_id" => section.id}
      end

      def self.verify!(inputs, output, actor:)
        page = StructuredActions.site(actor, inputs).pages.find(inputs.fetch("page_id"))
        section = page.sections.find(output.fetch("section_id"))
        raise StructuredTicket::Invalid, "Section acceptance failed" unless section.kind == inputs["kind"] && section.data.to_h.deep_stringify_keys == inputs["data"] && !page.published?
        true
      end
    end
  end
end
