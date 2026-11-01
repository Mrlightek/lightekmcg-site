# frozen_string_literal: true
module NevaehIntelligences
  module StructuredWorkers
    class CreatePage
      def self.perform(inputs, actor:, ticket:)
        website = StructuredActions.site(actor, inputs)
        page = website.pages.create!(title: inputs.fetch("title"), slug: inputs.fetch("slug"), published: false,
          position: website.pages.maximum(:position).to_i + 1)
        {"site_id" => website.id, "page_id" => page.id}
      end

      def self.verify!(inputs, output, actor:)
        page = StructuredActions.site(actor, inputs).pages.find(output.fetch("page_id"))
        raise StructuredTicket::Invalid, "Page acceptance failed" unless page.title == inputs["title"] && page.slug == inputs["slug"] && !page.published?
        true
      end
    end
  end
end
