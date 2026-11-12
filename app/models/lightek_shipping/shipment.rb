module LightekShipping
  class Shipment < ApplicationRecord
    self.table_name = "lightek_shipping_shipments"
    belongs_to :quote
    has_many_attached :labels
    before_validation { self.public_key ||= SecureRandom.uuid }
    validates :public_key, uniqueness: true, presence: true
    validates :status, inclusion: {in: %w[queued submitting ready review canceled]}
  end
end
