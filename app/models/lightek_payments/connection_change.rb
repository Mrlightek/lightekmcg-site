module LightekPayments
  class ConnectionChange < ApplicationRecord
    self.table_name = 'lightek_payout_connection_changes'
    belongs_to :user
    validates :previous_account_id, :replacement_account_id, :platform_account_id, presence: true
  end
end
