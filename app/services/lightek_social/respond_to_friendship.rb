# frozen_string_literal: true

module LightekSocial
  class RespondToFriendship
    ACTIONS =
      %w[
        accept
        decline
      ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(
      friendship:,
      actor_profile:,
      action:
    )
      @friendship =
        friendship

      @actor_profile =
        actor_profile

      @action =
        action.to_s
    end

    def call
      unless ACTIONS.include?(
        action
      )
        raise ArgumentError,
              "unsupported friendship action"
      end

      unless friendship.status ==
               "pending"
        raise AccessDenied,
              "friendship is not pending"
      end

      unless friendship.addressee_profile_id ==
               actor_profile.id
        raise AccessDenied,
              "only the addressee may respond"
      end

      if action ==
           "accept"
        accept!
      else
        decline!
      end
    end

    private

    attr_reader :friendship,
                :actor_profile,
                :action

    def accept!
      friendship.update!(
        status:
          "accepted",

        responded_at:
          Time.current,

        accepted_at:
          Time.current,

        ended_at:
          nil
      )

      event =
        RecordRelationshipEvent.call(
          actor_profile:
            actor_profile,

          target_profile:
            friendship.requester_profile,

          event_type:
            "friendship.accepted",

          counts_toward_strength:
            true,

          source_key:
            "friendship:" \
            "#{friendship.id}:" \
            "accepted:" \
            "#{friendship.accepted_at.to_i}"
        )

      RelationshipStrengthCalculator.call(
        event.actor_profile,
        event.target_profile
      )

      friendship
    end

    def decline!
      friendship.update!(
        status:
          "declined",

        responded_at:
          Time.current,

        accepted_at:
          nil
      )

      RecordRelationshipEvent.call(
        actor_profile:
          actor_profile,

        target_profile:
          friendship.requester_profile,

        event_type:
          "friendship.declined",

        counts_toward_strength:
          false,

        source_key:
          "friendship:" \
          "#{friendship.id}:" \
          "declined:" \
          "#{friendship.responded_at.to_i}"
      )

      friendship
    end
  end
end
