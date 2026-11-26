module Studio
  module MacroMaker
    class CompositionStore
      def initialize(site:, user:, catalog_options:)
        @site = site
        @user = user
        @catalog_options = catalog_options
      end

      def draft(definition)
        build(definition.reverse_merge("version" => 1))
      end

      def create!(definition, published:)
        id = definition["id"]
        surface = definition["surface"]
        unless id.is_a?(String) && Operation::Thick::ID.match?(id) && %w[image motion].include?(surface)
          raise ArgumentError, "Definition needs a Studio operation ID and an image or motion surface"
        end

        @site.with_lock do
          version = OperationRecord.where(site_id: @site.id, operation_id: id, surface: surface).maximum(:version).to_i + 1
          build(definition.merge("version" => version)).save!(published: published, owner: @user)
        end
      end

      def list(surface)
        scope = visible(surface)
        published = scope.where(published: true)
          .select("DISTINCT ON (operation_id, surface) studio_operation_records.*")
          .order(operation_id: :asc, surface: :asc, version: :desc)
        drafts = scope.where(published: false)
        (published.to_a + drafts.to_a).sort_by { |record| [record.operation_id, record.surface, -record.version] }
      end

      def find!(id, surface, version: nil)
        matches = visible(surface).where(operation_id: id)
        matches = matches.where(version: version) if version
        if !surface && matches.distinct.pluck(:surface).size > 1
          raise ArgumentError, "Choose a surface for composition #{id}"
        end
        matches.order(version: :desc).first!
      end

      private

      def visible(surface)
        scope = OperationRecord.compositions.where(site_id: @site.id)
        scope = scope.where(surface: surface) if surface
        scope.where(published: true).or(scope.where(published: false, owner_id: @user.id))
      end

      def build(definition)
        Composition.new(site: @site, definition: definition, catalog_options: @catalog_options, thick_only: true)
      end
    end
  end
end
