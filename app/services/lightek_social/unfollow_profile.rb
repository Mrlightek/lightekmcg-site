# frozen_string_literal: true

module LightekSocial
  class UnfollowProfile
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
      follow =
        Follow.find_by!(
          follower_profile:
            follower_profile,

          followed_profile:
            followed_profile
        )

      follow.destroy!

      RecordRelationshipEvent.call(
        actor_profile:
          follower_profile,

        target_profile:
          followed_profile,

        event_type:
          "follow.removed",

        counts_toward_strength:
          false,

        source_key:
          "follow:#{follow.id}:removed"
      )

      follow
    end

    private

    attr_reader :follower_profile,
                :followed_profile
  end
end
