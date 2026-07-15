# frozen_string_literal: true

module Marlon
  class BlueprintConcern < ApplicationRecord
    self.table_name = "marlon_blueprint_concerns"

    belongs_to :feature,
      class_name: "Marlon::Feature",
      inverse_of: :blueprint_concerns

    validates :name, :key, :target_type, presence: true
    validates :key, uniqueness: { scope: :feature_id },
      format: { with: /\A[a-z][a-z0-9_]*\z/ }
    validates :target_type, inclusion: { in: %w[model controller policy service job serializer graphql] }

    scope :active, -> { where(active: true) }

    def class_name
      (implementation_class.presence || key).to_s.camelize
    end
  end
end
