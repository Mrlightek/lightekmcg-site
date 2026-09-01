# app/models/network_port.rb

class NetworkPort < ApplicationRecord
  validates :port, presence: true,
                   numericality: {
                     only_integer: true,
                     greater_than: 0,
                     less_than_or_equal_to: 65_535
                   }

  validates :protocol, presence: true

  scope :enabled, -> { where(enabled: true) }

  def protocol
    self[:protocol].to_s.downcase
  end
end