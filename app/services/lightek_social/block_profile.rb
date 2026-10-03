# frozen_string_literal: true

module LightekSocial
  class BlockProfile
    def self.call(...)
      new(...).call
    end

    def initialize(
      blocker_profile:,
      blocked_profile:,
      reason_code: nil
    )
      @blocker_profile =
        blocker_profile

      @blocked_profile =
        blocked_profile

      @reason_code =
        reason_code
    end

    def call
      Block.transaction do
        block =
          Block.find_or_create_by!(
            blocker_profile:
              blocker_profile,

            blocked_profile:
              blocked_profile
          ) do |record|
            record.reason_code =
              reason_code
          end

        Follow.where(
          follower_profile_id: [
            blocker_profile.id,
            blocked_profile.id
          ],
          followed_profile_id: [
            blocker_profile.id,
            blocked_profile.id
          ]
        ).delete_all

        friendship =
          Friendship.find_by(
            pair_key:
              LightekSocial.pair_key(
                blocker_profile,
                blocked_profile
              )
          )

        if friendship &&
           !%w[
             ended
             declined
             cancelled
           ].include?(
             friendship.status
           )
          friendship.update!(
            status:
              "ended",

            ended_at:
              Time.current
          )
        end

        CircleMembership
          .joins(
            :circle
          )
          .where(
            profile_id:
              blocked_profile.id,
            lightek_social_circles: {
              owner_profile_id:
                blocker_profile.id
            }
          )
          .delete_all

        CircleMembership
          .joins(
            :circle
          )
          .where(
            profile_id:
              blocker_profile.id,
            lightek_social_circles: {
              owner_profile_id:
                blocked_profile.id
            }
          )
          .delete_all

        ConnectionOpportunity
          .where(
            profile_id: [
              blocker_profile.id,
              blocked_profile.id
            ],
            related_profile_id: [
              blocker_profile.id,
              blocked_profile.id
            ],
            status:
              "pending"
          )
          .update_all(
            status:
              "expired"
          )

        block
      end
    end

    private

    attr_reader :blocker_profile,
                :blocked_profile,
                :reason_code
  end
end
