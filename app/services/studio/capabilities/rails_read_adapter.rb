# frozen_string_literal: true
# STUDIO-203 isolated candidate. Read-only; not installed in Rails.
module Studio
  module Capabilities
    module RailsReadAdapter
      class Invalid < StandardError; end
      module_function
      MAX_ROWS = 100

      # Dependency injection allows completely isolated tests. The production reader
      # below is explicit and reads existing NevaehCapability rows only.
      def project_records(records:, provider_outputs:)
        raise Invalid, 'records must be an Array' unless records.is_a?(Array) && records.size <= MAX_ROWS
        raise Invalid, 'provider outputs invalid' unless provider_outputs.is_a?(Hash)
        rows = records.map do |rec|
          slug = rec.respond_to?(:slug) ? rec.slug : nil
          name = rec.respond_to?(:name) ? rec.name : nil
          enabled = rec.respond_to?(:enabled?) ? rec.enabled? : false
          metadata = rec.respond_to?(:metadata) ? rec.metadata : {}
          lifecycle = metadata.is_a?(Hash) ? (metadata['factory_lifecycle'] || 'unknown') : 'unknown'
          {'source'=>'nevaeh_capability','id'=>slug,'display_name'=>(name.is_a?(String) && !name.empty? ? name : slug),
           'enabled'=>enabled == true,'lifecycle'=>lifecycle.to_s}
        end
        # Reviewed provider contract explicitly supports build_scene only. OUTPUTS
        # describes emitted formats, not permission to start Blender.
        if provider_outputs.values.map(&:to_s).include?('blend') && provider_outputs.values.map(&:to_s).include?('glb')
          rows << {'source'=>'blender_provider','id'=>'studio.build_scene',
                   'display_name'=>'Blender build scene','enabled'=>false,'lifecycle'=>'provider_descriptor'}
        end
        Studio::Capabilities::Discovery.project(entries: rows)
      end

      # Invoke only from an authenticated and CanCanCan-authorized controller.
      # Read-only; returns a bounded public projection. No runtime handler data.
      def read_authorized_database
        raise Invalid, 'expected NevaehCapability model missing' unless defined?(::NevaehCapability)
        records = ::NevaehCapability.order(:slug).limit(MAX_ROWS + 1).to_a
        raise Invalid, 'capability limit exceeded' if records.length > MAX_ROWS
        project_records(records: records, provider_outputs: ::Studio::Providers::BlenderProvider::OUTPUTS)
      end

      def read_test_database
        raise Invalid, 'test Rails environment required' unless Rails.env.test?
        config = ActiveRecord::Base.connection_db_config.database.to_s
        raise Invalid, 'unexpected database' unless config == 'lightekmcg_site_test'
        raise Invalid, 'expected NevaehCapability model missing' unless defined?(::NevaehCapability)
        records = ::NevaehCapability.order(:slug).limit(MAX_ROWS + 1).to_a
        raise Invalid, 'capability limit exceeded' if records.length > MAX_ROWS
        project_records(records: records, provider_outputs: Studio::Providers::BlenderProvider::OUTPUTS)
      end
    end
  end
end
