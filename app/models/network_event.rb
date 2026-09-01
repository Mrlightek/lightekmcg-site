# app/models/network_event.rb

class NetworkEvent < ApplicationRecord
  validates :name, presence: true,
                   uniqueness: true

  scope :enabled, -> { where(enabled: true) }
end