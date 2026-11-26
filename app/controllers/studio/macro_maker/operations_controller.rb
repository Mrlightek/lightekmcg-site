module Studio
  module MacroMaker
    class OperationsController < BaseController
      def show
        id = request.path_parameters.fetch(:id)
        matches = thick_operations.select { |operation| operation.id == id }
        if !@surface && matches.size > 1
          raise ArgumentError, "Choose a surface for operation #{id}"
        end
        entry = matches.find { |operation| operation.surface.to_s == @surface } || matches.first
        raise ActiveRecord::RecordNotFound unless entry

        render json: serializer.operation_detail(entry)
      end
    end
  end
end
