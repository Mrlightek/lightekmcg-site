# frozen_string_literal: true

module Marlon
  class CapabilityPackDependency < ApplicationRecord
    self.table_name = "marlon_capability_pack_dependencies"

    belongs_to :capability_pack,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :outgoing_dependencies
    belongs_to :dependency,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :incoming_dependencies

    validates :dependency_id, uniqueness: { scope: :capability_pack_id }
    validate :cannot_depend_on_self

    private

    def cannot_depend_on_self
      errors.add(:dependency, "cannot be itself") if capability_pack_id == dependency_id
    end
  end
end
