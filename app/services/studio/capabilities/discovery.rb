# frozen_string_literal: true
# STUDIO-203 candidate. Pure projection. No AR, Blender, Gatekeeper or registry calls.
module Studio
  module Capabilities
    module Discovery
      class Invalid < StandardError; end
      ID = /\A[a-z][a-z0-9]*(?:[._][a-z0-9]+)*\z/
      SOURCES = %w[nevaeh_capability blender_provider].freeze
      module_function

      # Entries must come from a separately authorized reader, NOT untrusted issue text.
      # Every result is deliberately non-authoritative for execution.
      def project(entries:)
        raise Invalid, 'entries must be an array' unless entries.is_a?(Array)
        raise Invalid, 'too many entries' if entries.size > 10000
        seen = {}
        records = entries.map do |row|
          raise Invalid, 'entry must be a mapping' unless row.is_a?(Hash)
          source = row.fetch('source') { raise Invalid, 'source missing' }
          id = row.fetch('id') { raise Invalid, 'id missing' }
          raise Invalid, 'source not allowlisted' unless SOURCES.include?(source)
          raise Invalid, 'invalid identifier' unless id.is_a?(String) && id.bytesize <= 100 && ID.match?(id)
          identity = [source,id]
          raise Invalid, 'duplicate source/id: '+identity.join(':') if seen[identity]
          seen[identity]=true
          name=row.fetch('display_name',id)
          raise Invalid, 'invalid display name' unless name.is_a?(String) && name.bytesize.between?(1,200)
          enabled=row.fetch('enabled',false)
          raise Invalid, 'enabled must be boolean' unless enabled == true || enabled == false
          desc=row.fetch('description',nil)
          raise Invalid, 'invalid description' unless desc.nil? || (desc.is_a?(String) && desc.bytesize <= 1000)
          # Do not carry arbitrary runtime handler names, secrets, or user-defined code into discovery.
          {'schema_version'=>1,'id'=>id,'source'=>source,'display_name'=>name,
           'description'=>desc,'registered'=>true,'configured_enabled'=>enabled,
           'available'=>false,'executable'=>false,'approval'=>'unknown',
           'lifecycle'=>row.fetch('lifecycle','unknown').to_s[0,40]}
        end
        {'schema_version'=>1,'read_only'=>true,'execution_authorized'=>false,
         'records'=>records.sort_by { |r| [r.fetch('id'),r.fetch('source')] }}
      end
    end
  end
end
