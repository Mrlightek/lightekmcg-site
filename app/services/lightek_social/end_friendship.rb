# frozen_string_literal: true

module LightekSocial
  class EndFriendship
    def self.call(...)
      new(...).call
    end

    def initialize(
      friendship:,
      actor_profile:
    )
      @friendship =
        friendship

      @actor_profile =
        actor_profile
    end

    def call
      unless friendship.involves?(
        actor_profile
      )
        raise AccessDenied,
              "profile is not part of friendship"
      end

      other =
        friendship.other_profile_for(
          actor_profile
        )

      friendship.update!(
        status:
          "ended",

        ended_at:
          Time.current
      )

      RecordRelationshipEvent.call(
        actor_profile:
          actor_profile,

        target_profile:
          other,

        event_type:
          "friendship.ended",

        counts_toward_strength:
          false,

        source_key:
          "friendship:" \
          "#{friendship.id}:" \
          "ended:" \
          "#{friendship.ended_at.to_i}"
      )

      friendship
    end

    private

    attr_reader :friendship,
                :actor_profile
  end
end
