# frozen_string_literal: true

module Marlon
  class CapabilityPackFeature < ApplicationRecord
    self.table_name = "marlon_capability_pack_features"

    belongs_to :capability_pack,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :capability_pack_features
    belongs_to :feature,
      class_name: "Marlon::Feature",
      inverse_of: :capability_pack_features

    validates :feature_id, uniqueness: { scope: :capability_pack_id }
  end
end
