module LightekPwa
  class CreatorOffer < ApplicationRecord
    self.table_name = 'lightek_pwa_creator_offers'
    belongs_to :site, class_name: 'DymondSite::Site'
    belongs_to :creator, class_name: 'User'
    validates :creator_id, uniqueness: {scope: :site_id}
    validates :monthly_cents, numericality: {only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 100_000}
  end
end
