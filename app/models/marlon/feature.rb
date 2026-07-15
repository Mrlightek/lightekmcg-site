# frozen_string_literal: true

module Marlon
  class Feature < ApplicationRecord
    self.table_name = "marlon_features"

    has_many :capability_pack_features,
      class_name: "Marlon::CapabilityPackFeature",
      dependent: :destroy,
      inverse_of: :feature
    has_many :capability_packs,
      through: :capability_pack_features,
      class_name: "Marlon::CapabilityPack"

    has_many :blueprint_concerns,
      class_name: "Marlon::BlueprintConcern",
      dependent: :destroy,
      inverse_of: :feature

    validates :name, :key, presence: true
    validates :key, uniqueness: true,
      format: { with: /\A[a-z][a-z0-9_]*\z/ }

    scope :active, -> { where(active: true) }
  end
end
