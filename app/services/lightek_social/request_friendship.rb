# frozen_string_literal: true

module LightekSocial
  class RequestFriendship
    def self.call(...)
      new(...).call
    end

    def initialize(
      requester_profile:,
      addressee_profile:
    )
      @requester_profile =
        requester_profile

      @addressee_profile =
        addressee_profile
    end

    def call
      raise AccessDenied,
            "blocked relationship" if
        LightekSocial.blocked_between?(
          requester_profile,
          addressee_profile
        )

      pair_key =
        LightekSocial.pair_key(
          requester_profile,
          addressee_profile
        )

      friendship =
        Friendship.find_by(
          pair_key:
            pair_key
        )

      Friendship.transaction do
        if friendship&.status ==
             "accepted"
          return friendship
        end

        if friendship&.status ==
             "pending"
          if friendship.requester_profile_id ==
               requester_profile.id
            return friendship
          end

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

          record_accepted!(
            friendship
          )

          return friendship
        end

        friendship ||=
          Friendship.new

        friendship.assign_attributes(
          requester_profile:
            requester_profile,

          addressee_profile:
            addressee_profile,

          status:
            "pending",

          responded_at:
            nil,

          accepted_at:
            nil,

          ended_at:
            nil
        )

        friendship.save!

        RecordRelationshipEvent.call(
          actor_profile:
            requester_profile,

          target_profile:
            addressee_profile,

          event_type:
            "friendship.requested",

          counts_toward_strength:
            false,

          source_key:
            "friendship:" \
            "#{friendship.id}:" \
            "request:" \
            "#{friendship.updated_at.to_i}"
        )

        friendship
      end
    end

    private

    attr_reader :requester_profile,
                :addressee_profile

    def record_accepted!(
      friendship
    )
      event =
        RecordRelationshipEvent.call(
          actor_profile:
            requester_profile,

          target_profile:
            addressee_profile,

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
    end
  end
end
