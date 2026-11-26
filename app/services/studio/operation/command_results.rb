module Studio
  module Operation
    module CommandResults
      # Registry introspection has no result schema. These paths are verified against the CLI replies.
      PATHS = {
        "photocraft" => {
          "layer.new.layer" => {"layer" => ["layer"]},
          "layer.new.group" => {"layer" => ["layer"]}
        },
        "effectcraft" => {
          "comp.new" => {"comp" => ["comp"]},
          "layer.newSolid" => {"layer" => ["layer"]}
        }
      }.freeze

      def self.for(engine, command)
        PATHS.fetch(engine).fetch(command, {})
      end
    end
  end
end
