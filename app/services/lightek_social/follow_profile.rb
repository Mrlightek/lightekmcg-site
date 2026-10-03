# frozen_string_literal: true

module LightekSocial
  class FollowProfile
    def self.call(...)
      new(...).call
    end

    def initialize(
      follower_profile:,
      followed_profile:
    )
      @follower_profile =
        follower_profile

      @followed_profile =
        followed_profile
    end

    def call
      raise AccessDenied,
            "blocked relationship" if
        LightekSocial.blocked_between?(
          follower_profile,
          followed_profile
        )

      follow =
        Follow.find_or_create_by!(
          follower_profile:
            follower_profile,

          followed_profile:
            followed_profile
        )

      RecordRelationshipEvent.call(
        actor_profile:
          follower_profile,

        target_profile:
          followed_profile,

        event_type:
          "follow.created",

        counts_toward_strength:
          false,

        source_key:
          "follow:#{follow.id}:created"
      )

      follow
    end

    private

    attr_reader :follower_profile,
                :followed_profile
  end
end
