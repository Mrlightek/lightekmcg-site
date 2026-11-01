# frozen_string_literal: true
module Studio
  module NativeBlender
    class DemoCatalog
      def self.items
        JSON.parse(File.read(File.expand_path("../../../../config/studio/blender_demos.json",__dir__)))
      end
      def self.fetch(key)
        items.find { |item| item["key"]==key.to_s } || raise(ArgumentError,"Choose an available Blender demo")
      end
    end
  end
end
