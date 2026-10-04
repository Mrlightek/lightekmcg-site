# frozen_string_literal: true

module LightekMessaging
  class AddGroupParticipants
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      actor_profile:,
      target_profiles:,
      at: Time.current
    )
      @conversation =
        conversation

      @actor_profile =
        actor_profile

      @target_profiles =
        Array(
          target_profiles
        )
          .compact
          .uniq do |profile|
            profile.id
          end

      @at =
        at
    end

    def call
      authorize_group!

      profiles =
        target_profiles.reject do |candidate|
          candidate.id ==
            actor_profile.id
        end

      if profiles.empty?
        raise ArgumentError,
              "At least one other profile is required"
      end

      Participant.transaction do
        profiles.map do |candidate|
          add_or_reactivate!(
            candidate
          )
        end
      end
    end

    private

    attr_reader :conversation,
                :actor_profile,
                :target_profiles,
                :at

    def authorize_group!
      unless conversation.group?
        raise ArgumentError,
              "Members can only be added to group conversations"
      end

      actor_member =
        conversation
          .active_participant_for(
            actor_profile
          )

      unless actor_member
        raise AccessDenied,
              "Conversation is unavailable"
      end

      unless actor_member.admin?
        raise AccessDenied,
              "Only a group owner or administrator can add members"
      end
    end

    def add_or_reactivate!(candidate)
      member =
        conversation
          .participants
          .find_by(
            profile_id:
              candidate.id
          )

      return member if member&.active?

      if member
        member.update!(
          role:
            "member",

          joined_at:
            at,

          left_at:
            nil,

          last_read_at:
            nil
        )

        return member
      end

      Participant.create!(
        conversation:
          conversation,

        profile:
          candidate,

        role:
          "member",

        joined_at:
          at,

        left_at:
          nil,

        last_read_at:
          nil
      )
    end
  end
end
