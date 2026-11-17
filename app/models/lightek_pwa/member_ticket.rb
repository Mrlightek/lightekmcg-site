module LightekPwa
  class MemberTicket < ApplicationRecord
    self.table_name = 'lightek_pwa_member_tickets'
    belongs_to :member_backend, class_name: 'LightekPwa::MemberBackend'
  end
end
