# frozen_string_literal: true

module Studio
  module Advertising
    class SponsorPackageSpot < ApplicationRecord
      self.table_name = "studio_sponsor_package_spots"
      belongs_to :package, class_name: "Studio::Advertising::SponsorPackage"
      belongs_to :payment, class_name: "Studio::Advertising::Payment"
      attr_readonly :package_id, :payment_id
    end
  end
end
