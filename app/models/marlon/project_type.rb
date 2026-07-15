# frozen_string_literal: true

module Marlon
  class ProjectType < ApplicationRecord
    self.table_name = "marlon_project_types"

    has_many :project_type_capability_packs,
      class_name: "Marlon::ProjectTypeCapabilityPack",
      dependent: :destroy,
      inverse_of: :project_type
    has_many :capability_packs,
      through: :project_type_capability_packs,
      class_name: "Marlon::CapabilityPack"

    validates :name, :key, presence: true
    validates :key, uniqueness: true,
      format: { with: /\A[a-z][a-z0-9_]*\z/ }

    scope :active, -> { where(active: true) }

    def resolved_capability_packs
      Marlon::Blueprint::Resolver.new(capability_packs).resolve
    end

    def resolved_features
      resolved_capability_packs.flat_map(&:features).uniq(&:id)
    end
  end
end
