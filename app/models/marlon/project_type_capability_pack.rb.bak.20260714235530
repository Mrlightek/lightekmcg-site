# frozen_string_literal: true

module Marlon
  class ProjectTypeCapabilityPack < ApplicationRecord
    self.table_name = "marlon_project_type_capability_packs"

    belongs_to :project_type,
      class_name: "Marlon::ProjectType",
      inverse_of: :project_type_capability_packs
    belongs_to :capability_pack,
      class_name: "Marlon::CapabilityPack",
      inverse_of: :project_type_capability_packs

    validates :capability_pack_id, uniqueness: { scope: :project_type_id }
  end
end
