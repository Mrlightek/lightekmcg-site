module LightekIdentity
  class Realm < ApplicationRecord
    self.table_name = 'lightek_identity_realms'
    belongs_to :employer, class_name: 'User'
    has_many :node_bindings
    before_validation { self.domain = domain.to_s.downcase.strip }
    before_save { self.directory_revision += 1 if new_record? || will_save_change_to_domain? || will_save_change_to_enabled? || will_save_change_to_auto_join? }
    validates :employer_id, uniqueness: true
    validates :domain, format: {with: /\A[a-z0-9](?:[a-z0-9.-]{0,250}[a-z0-9])?\.[a-z]{2,}\z/}
  end
end
