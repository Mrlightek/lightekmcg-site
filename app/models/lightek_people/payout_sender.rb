module LightekPeople
  class PayoutSender < ApplicationRecord
    self.table_name = 'lightek_people_payout_senders'
    belongs_to :employer, class_name: 'User'
    validates :employer_id, :financial_account_ref, uniqueness: true
    validates :financial_account_ref, presence: true
  end
end
