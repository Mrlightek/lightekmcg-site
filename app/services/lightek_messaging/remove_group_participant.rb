# frozen_string_literal: true

module LightekMessaging
  class RemoveGroupParticipant
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      actor_profile:,
      target_profile:,
      at: Time.current
    )
      @conversation =
        conversation

      @actor_profile =
        actor_profile

      @target_profile =
        target_profile

      @at =
        at
    end

    def call
      unless conversation.group?
        raise ArgumentError,
              "Members can only be removed from group conversations"
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
              "Only a group owner or administrator can remove members"
      end

      target_member =
        conversation
          .active_participant_for(
            target_profile
          )

      unless target_member
        raise AccessDenied,
              "Target profile is not an active member"
      end

      if actor_member.id ==
           target_member.id
        raise ArgumentError,
              "Use Leave group to remove yourself"
      end

      if target_member.owner?
        raise AccessDenied,
              "The group owner cannot be removed"
      end

      if !actor_member.owner? &&
           target_member.role !=
             "member"
        raise AccessDenied,
              "Administrators can only remove regular members"
      end

      target_member.update!(
        left_at:
          at
      )

      target_member
    end

    private

    attr_reader :conversation,
                :actor_profile,
                :target_profile,
                :at
  end
end
