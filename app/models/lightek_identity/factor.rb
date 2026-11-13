module LightekIdentity
  class Factor < ApplicationRecord
    self.table_name = 'lightek_identity_factors'
    belongs_to :user
    validates :user_id, uniqueness: true
    def enabled? = enabled_at.present?
  end
end
