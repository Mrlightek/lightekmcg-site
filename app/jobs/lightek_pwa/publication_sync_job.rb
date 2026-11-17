module LightekPwa
  class PublicationSyncJob < ApplicationJob
    queue_as :default
    retry_on LightekReservations::Federation::Client::Unavailable, wait: :polynomially_longer, attempts: 12
    def perform(id)
      row = PublicationOutbox.find(id)
      return if row.delivered_revision >= row.revision
      revision = row.revision
      LightekReservations::Federation::Client.new(row.site).request('pwa/publications', method: :post,
        body: row.payload.merge('revision' => revision))
      row.with_lock { row.update!(delivered_revision: [row.delivered_revision, revision].max) }
    end
  end
end
