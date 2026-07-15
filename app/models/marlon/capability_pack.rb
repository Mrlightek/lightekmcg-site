# frozen_string_literal: true

module Marlon
  class CapabilityPack < ApplicationRecord
    self.table_name = "marlon_capability_packs"

    has_many :capability_pack_features,
      class_name: "Marlon::CapabilityPackFeature",
      dependent: :destroy,
      inverse_of: :capability_pack
    has_many :features,
      through: :capability_pack_features,
      class_name: "Marlon::Feature"

    has_many :outgoing_dependencies,
      class_name: "Marlon::CapabilityPackDependency",
      foreign_key: :capability_pack_id,
      dependent: :destroy,
      inverse_of: :capability_pack
    has_many :dependencies,
      through: :outgoing_dependencies,
      source: :dependency,
      class_name: "Marlon::CapabilityPack"

    has_many :incoming_dependencies,
      class_name: "Marlon::CapabilityPackDependency",
      foreign_key: :dependency_id,
      dependent: :destroy,
      inverse_of: :dependency

    has_many :project_type_capability_packs,
      class_name: "Marlon::ProjectTypeCapabilityPack",
      dependent: :destroy,
      inverse_of: :capability_pack
    has_many :project_types,
      through: :project_type_capability_packs,
      class_name: "Marlon::ProjectType"

    validates :name, :key, presence: true
    validates :key, uniqueness: true,
      format: { with: /\A[a-z][a-z0-9_]*\z/ }

    scope :active, -> { where(active: true) }
  end
end
