# frozen_string_literal: true

module LightekSocial
  class RecordRelationshipEvent
    def self.call(...)
      new(...).call
    end

    def initialize(
      actor_profile:,
      target_profile:,
      event_type:,
      context: nil,
      occurred_at: Time.current,
      source_key: nil,
      counts_toward_strength: true,
      metadata: {}
    )
      @actor_profile =
        actor_profile

      @target_profile =
        target_profile

      @event_type =
        event_type.to_s

      @context =
        context

      @occurred_at =
        occurred_at

      @source_key =
        source_key

      @counts_toward_strength =
        counts_toward_strength

      @metadata =
        metadata.to_h
    end

    def call
      raise AccessDenied,
            "blocked relationship" if
        LightekSocial.blocked_between?(
          actor_profile,
          target_profile
        )

      if source_key.present?
        existing =
          RelationshipEvent.find_by(
            source_key:
              source_key
          )

        return existing if existing
      end

      RelationshipEvent.create!(
        actor_profile:
          actor_profile,

        target_profile:
          target_profile,

        event_type:
          event_type,

        context:
          context,

        occurred_at:
          occurred_at,

        source_key:
          source_key,

        counts_toward_strength:
          counts_toward_strength,

        metadata:
          metadata
      )
    end

    private

    attr_reader :actor_profile,
                :target_profile,
                :event_type,
                :context,
                :occurred_at,
                :source_key,
                :counts_toward_strength,
                :metadata
  end
end
