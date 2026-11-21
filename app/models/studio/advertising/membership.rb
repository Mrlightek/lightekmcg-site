# frozen_string_literal: true

module Studio
  module Advertising
    class Membership < ApplicationRecord
      self.table_name = "studio_ad_memberships"

      belongs_to :network, class_name: "Studio::Advertising::Network"
      belongs_to :station_site, class_name: "DymondSite::Site"
    end
  end
end
