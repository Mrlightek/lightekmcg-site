namespace :lightek do
  namespace :pwa do
    desc 'Retry pending instance publication references without copying content'
    task sync_publications: :environment do
      LightekPwa::PublicationOutbox.where('delivered_revision < revision').find_each do |row|
        LightekPwa::PublicationSyncJob.perform_later(row.id)
      end
    end
  end
end
