# frozen_string_literal: true

module Studio
  module Advertising
    class Network < ApplicationRecord
      self.table_name = "studio_ad_networks"

      belongs_to :site, class_name: "DymondSite::Site"
      belongs_to :peer, class_name: "LightekReservations::Peer", optional: true
      has_many :campaigns, class_name: "Studio::Advertising::Campaign", dependent: :restrict_with_error

      has_many :memberships, class_name: "Studio::Advertising::Membership", dependent: :restrict_with_error

      validates :name, presence: true, length: { maximum: 100 }
    end
  end
end
