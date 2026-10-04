# frozen_string_literal: true

module LightekSocial
  class UnblockProfile
    def self.call(...)
      new(...).call
    end

    def initialize(
      blocker_profile:,
      blocked_profile:
    )
      @blocker_profile =
        blocker_profile

      @blocked_profile =
        blocked_profile
    end

    def call
      block =
        Block.find_by!(
          blocker_profile:
            blocker_profile,

          blocked_profile:
            blocked_profile
        )

      block.destroy!

      RecordRelationshipEvent.call(
        actor_profile:
          blocker_profile,

        target_profile:
          blocked_profile,

        event_type:
          "block.removed",

        counts_toward_strength:
          false,

        source_key:
          "block:#{block.id}:removed"
      )

      block
    end

    private

    attr_reader :blocker_profile,
                :blocked_profile
  end
end
