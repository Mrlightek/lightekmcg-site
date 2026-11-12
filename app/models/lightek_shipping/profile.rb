module LightekShipping
  class Profile < ApplicationRecord
    self.table_name = "lightek_shipping_profiles"
    belongs_to :site, class_name: "DymondSite::Site"
    validates :site_id, uniqueness: true
    validates :customer_markup_bps, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000}
    validate do
      Payload.party!(origin) if origin.present?
      Payload.package!(default_package) if default_package.present?
    rescue ArgumentError => error
      errors.add(:base, error.message)
    end
  end
end
