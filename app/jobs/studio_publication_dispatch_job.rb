# frozen_string_literal: true

class StudioPublicationDispatchJob < ApplicationJob
  queue_as :studio

  def perform(publication_id)
    publication = StudioPublication.find(publication_id)

    return if publication.status.in?(%w[published cancelled publishing])

    if publication.status == "scheduled" &&
       publication.scheduled_at.present? &&
       publication.scheduled_at.future?

      self.class
          .set(wait_until: publication.scheduled_at)
          .perform_later(publication.id)

      return
    end

    Studio::Publishing::Dispatch.new(publication).call
  end
end
