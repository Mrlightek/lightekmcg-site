# frozen_string_literal: true

module LightekMessaging
  class ChangeGroupParticipantRole
    ALLOWED_ROLES =
      %w[
        admin
        member
      ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      actor_profile:,
      target_profile:,
      role:
    )
      @conversation =
        conversation

      @actor_profile =
        actor_profile

      @target_profile =
        target_profile

      @role =
        role.to_s
    end

    def call
      unless conversation.group?
        raise ArgumentError,
              "Roles can only be managed in group conversations"
      end

      unless ALLOWED_ROLES.include?(
        role
      )
        raise ArgumentError,
              "Unsupported group role"
      end

      actor_member =
        conversation
          .active_participant_for(
            actor_profile
          )

      unless actor_member&.owner?
        raise AccessDenied,
              "Only the group owner can manage administrator roles"
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

      if target_member.id ==
           actor_member.id
        raise AccessDenied,
              "The group owner role cannot be changed here"
      end

      if target_member.owner?
        raise AccessDenied,
              "The group owner cannot be demoted"
      end

      case role
      when "admin"
        unless target_member.role ==
                 "member"
          raise ArgumentError,
                "Only regular members can be promoted"
        end

      when "member"
        unless target_member.role ==
                 "admin"
          raise ArgumentError,
                "Only administrators can be demoted"
        end
      end

      target_member.update!(
        role:
          role
      )

      target_member
    end

    private

    attr_reader :conversation,
                :actor_profile,
                :target_profile,
                :role
  end
end
