# frozen_string_literal: true

module Studio
  module Factory
    # Lifecycle API for trusted/generated capabilities. Never evaluates JSON as code.
    # Proof receipts can be attached to the originating Lightek ticket.
    class CapabilityCrud
      class NotPublishable < StandardError; end
      class UnsupportedOperation < StandardError; end

      OPERATIONS = %w[create read update publish archive].freeze
      EDITABLE = %w[name description].freeze

      def self.perform(operation:, slug:, attributes: {}, ticket: nil)
        new(operation: operation, slug: slug, attributes: attributes, ticket: ticket).perform
      end

      def initialize(operation:, slug:, attributes:, ticket:)
        @operation = operation.to_s
        @slug = slug.to_s
        @attributes = attributes.to_h.deep_stringify_keys
        @ticket = ticket
      end

      def perform
        raise UnsupportedOperation, operation unless OPERATIONS.include?(operation)
        raise ArgumentError, 'Invalid capability slug' unless /\A[a-z][a-z0-9_.]*\z/.match?(slug)
        raise ArgumentError, 'Unrecognized capability fields' unless (attributes.keys - EDITABLE - %w[definition]).empty?
        raise ArgumentError, 'Ticket must be a Marlon::Ticket' if ticket && !ticket.is_a?(Marlon::Ticket)

        NevaehCapability.transaction do
          record = case operation
                   when 'create' then create_draft!
                   when 'read' then NevaehCapability.find_by!(slug: slug)
                   when 'update' then update_draft!
                   when 'publish' then publish!
                   when 'archive' then archive!
                   end
          receipt = {
            'operation' => operation,
            'capability' => slug,
            'record_id' => record.id,
            'lifecycle' => lifecycle(record),
            'enabled' => record.enabled?,
            'handler' => record.handler,
            'contract' => record.metadata.to_h.fetch('factory_definition', {}),
            'record_updated_at' => record.updated_at&.iso8601
          }
          ticket&.log!(action: "Factory capability #{operation}", detail: receipt.to_json)
          receipt
        end
      end

      private

      attr_reader :operation, :slug, :attributes, :ticket

      def create_draft!
        raise ArgumentError, 'Capability already exists' if NevaehCapability.exists?(slug: slug)
        definition = attributes.fetch('definition', {})
        raise ArgumentError, 'Definition must be an object' unless definition.is_a?(Hash)
        NevaehCapability.create!(
          slug: slug, name: attributes.fetch('name'),
          description: attributes['description'].to_s,
          domain: 'studio', intent_name: slug.tr('.', '_'),
          handler: 'Studio::Blueprint::Runtime', queue: 'default', priority: 5,
          gatekeeper_capability: slug, enabled: false,
          metadata: {'factory_lifecycle' => 'draft', 'factory_definition' => definition}
        )
      end

      def update_draft!
        record = NevaehCapability.lock.find_by!(slug: slug)
        raise NotPublishable, 'Only draft capabilities can be edited' unless lifecycle(record) == 'draft'
        metadata = record.metadata.to_h.deep_stringify_keys
        if attributes.key?('definition')
          raise ArgumentError, 'Definition must be an object' unless attributes['definition'].is_a?(Hash)
          metadata['factory_definition'] = attributes['definition']
        end
        record.update!(attributes.slice(*EDITABLE).merge('metadata' => metadata))
        record
      end

      def publish!
        record = NevaehCapability.lock.find_by!(slug: slug)
        definition = record.metadata.to_h.deep_stringify_keys.fetch('factory_definition', {})
        # Publishing requires a trusted implementation binding, not an arbitrary Ruby constant from JSON.
        binding = definition['execution_handler'].to_s
        raise NotPublishable, 'An approved implementation binding is required' if binding.blank?
        approved = Array(Rails.configuration.x.try(:studio_factory_approved_handlers)).map(&:to_s)
        raise NotPublishable, 'Implementation handler is not allowlisted' unless approved.include?(binding)
        handler = binding.safe_constantize
        raise NotPublishable, 'Implementation handler cannot execute' unless handler&.respond_to?(:perform)
        record.update!(enabled: true, handler: binding,
          metadata: record.metadata.to_h.merge('factory_lifecycle' => 'published'))
        record
      end

      def archive!
        record = NevaehCapability.lock.find_by!(slug: slug)
        record.update!(enabled: false,
          metadata: record.metadata.to_h.merge('factory_lifecycle' => 'archived'))
        record
      end

      def lifecycle(record)
        record.metadata.to_h.fetch('factory_lifecycle', record.enabled? ? 'published' : 'draft')
      end
    end
  end
end
