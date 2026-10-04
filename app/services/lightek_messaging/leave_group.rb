# frozen_string_literal: true

module LightekMessaging
  class LeaveGroup
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      profile:,
      at: Time.current
    )
      @conversation =
        conversation

      @profile =
        profile

      @at =
        at
    end

    def call
      unless conversation.group?
        raise ArgumentError,
              "Only group conversations can be left"
      end

      Participant.transaction do
        member =
          conversation
            .active_participant_for(
              profile
            )

        unless member
          raise AccessDenied,
                "Conversation is unavailable"
        end

        transfer_ownership!(
          member
        ) if member.owner?

        member.update!(
          left_at:
            at
        )

        member
      end
    end

    private

    attr_reader :conversation,
                :profile,
                :at

    def transfer_ownership!(leaving_member)
      candidates =
        conversation
          .participants
          .active
          .where
          .not(
            id:
              leaving_member.id
          )
          .order(
            :id
          )
          .to_a

      successor =
        candidates.min_by do |candidate|
          [
            candidate.admin? ? 0 : 1,
            candidate.id
          ]
        end

      successor&.update!(
        role:
          "owner"
      )
    end
  end
end
