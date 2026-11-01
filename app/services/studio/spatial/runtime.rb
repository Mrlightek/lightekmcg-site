# frozen_string_literal: true
module Studio
  module Spatial
    class Runtime
      def self.config
        path=Rails.root.join("tmp/studio-spatial-runtime.json")
        stored=path.file? ? JSON.parse(path.read) : {}
        stored.merge(ENV.to_h.slice(*stored.keys,"STUDIO_SPATIAL_ROOT","STUDIO_SPATIAL_SECRET","STUDIO_SPATIAL_URL","STUDIO_SPATIAL_PYTHON"))
      end
      def self.fetch(key,default=nil)=config.fetch(key,default)
    end
  end
end
