module Studio
  module MacroMaker
    class CatalogController < BaseController
      def index
        render json: serializer.catalog(thick_operations, engines: RecipeSession::ADAPTERS.keys)
      end
    end
  end
end
