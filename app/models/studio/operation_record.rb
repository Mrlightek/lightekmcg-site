require_relative "../../services/studio/operation/thick"

module Studio
  class OperationRecord < ApplicationRecord
    self.table_name = "studio_operation_records"

    belongs_to :site, class_name: "DymondSite::Site", optional: false
    belongs_to :owner, class_name: "User", optional: true

    validates :operation_id, format: {with: Operation::Thick::ID}
    validates :surface, inclusion: {in: Operation::Thick::SURFACES}
    validates :version, numericality: {only_integer: true, greater_than: 0},
      uniqueness: {scope: [:site_id, :operation_id, :surface]}
    validates :published, inclusion: {in: [true, false]}
    validate :valid_operation_body

    scope :published, -> { where(published: true) }
    scope :compositions, -> { where("jsonb_exists(body, 'composition')") }

    def operation(engine_adapters: {}, catalog_options: {})
      metadata = body["composition"] if body.is_a?(Hash)
      guard = if metadata
        options = engine_adapters.empty? ? catalog_options : {engine_adapters: engine_adapters}.merge(catalog_options)
        ->(ancestry) do
          Composition.from_record(self, catalog_options: options).verify!(
            body.fetch("recipe"), metadata.fetch("references"), ancestry: ancestry)
        end
      end
      Operation::Thick.new(body, origin: :tenant, engine_adapters: engine_adapters, before_run: guard)
    end

    private

    def valid_operation_body
      configured = operation
      if body.key?("composition")
        metadata = body["composition"]
        unless metadata.is_a?(Hash) && metadata["definition"].is_a?(Hash) && metadata["references"].is_a?(Array)
          errors.add(:body, "must contain a composition definition and reference list")
        end
      end
      return if configured.id == operation_id && configured.surface.to_s == surface && configured.recipe.version == version

      errors.add(:body, "must match the operation ID, surface and recipe version")
    rescue ArgumentError => error
      errors.add(:body, error.message)
    end
  end
end
