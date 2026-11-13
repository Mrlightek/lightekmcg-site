module LightekPeople
  class PayoutDestination < ApplicationRecord
    self.table_name = 'lightek_people_payout_destinations'
    belongs_to :employment
    validates :employment_id, uniqueness: true
    validates :provider, inclusion: {in: %w[stripe_global]}
  end
end
