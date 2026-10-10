# frozen_string_literal: true

module Studio
  module Blueprint
    # Dynamic availability: every lookup reflects current database state.
    class Registry
      def self.published
        NevaehCapability.enabled.for_domain("studio").select do |record|
          data = record.metadata.to_h
          data["generated"] == true &&
            data["blueprint_status"] == "published" &&
            data["execution_ready"] == true
        end
      end

      def self.resolve(slug)
        published.find { |record| record.slug == slug.to_s }
      end
    end
  end
end
