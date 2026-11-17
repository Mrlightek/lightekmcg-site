module LightekPwa
  class PublicationOutbox < ApplicationRecord
    self.table_name = 'lightek_pwa_publication_outboxes'
    belongs_to :site, class_name: 'DymondSite::Site'
  end
end
