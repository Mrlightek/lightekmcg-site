# frozen_string_literal: true

module Marlon
  class GeneratedArtifact < ApplicationRecord
    self.table_name = "marlon_generated_artifacts"

    validates :blueprint_key, :artifact_type, :path, presence: true
    validates :path, uniqueness: { scope: :blueprint_key }
  end
end
