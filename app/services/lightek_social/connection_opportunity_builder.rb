# frozen_string_literal: true

module LightekSocial
  class ConnectionOpportunityBuilder
    def self.call(...)
      new(...).call
    end

    def initialize(
      profile:,
      related_profile:,
      kind:,
      reasons:,
      reason_code: nil,
      context: nil,
      source_key: nil,
      expires_at: nil,
      metadata: {}
    )
      @profile =
        profile

      @related_profile =
        related_profile

      @kind =
        kind.to_s

      @reasons =
        Array(
          reasons
        ).map(&:to_s)
         .reject(&:blank?)

      @reason_code =
        reason_code

      @context =
        context

      @source_key =
        source_key

      @expires_at =
        expires_at

      @metadata =
        metadata.to_h
    end

    def call
      raise AccessDenied,
            "blocked relationship" if
        LightekSocial.blocked_between?(
          profile,
          related_profile
        )

      unless meaningful_existing_relationship?
        raise AccessDenied,
              "connection opportunity requires an existing relationship"
      end

      if source_key.present?
        existing =
          ConnectionOpportunity.find_by(
            source_key:
              source_key
          )

        return existing if existing
      end

      ConnectionOpportunity.create!(
        profile:
          profile,

        related_profile:
          related_profile,

        kind:
          kind,

        reason_code:
          reason_code,

        context:
          context,

        source_key:
          source_key,

        detected_at:
          Time.current,

        expires_at:
          expires_at,

        metadata:
          metadata.merge(
            "reasons" =>
              reasons
          )
      )
    end

    private

    attr_reader :profile,
                :related_profile,
                :kind,
                :reasons,
                :reason_code,
                :context,
                :source_key,
                :expires_at,
                :metadata

    def meaningful_existing_relationship?
      return true if
        Friendship.accepted.exists?(
          pair_key:
            LightekSocial.pair_key(
              profile,
              related_profile
            )
        )

      CircleMembership
        .joins(
          :circle
        )
        .exists?(
          profile_id:
            related_profile.id,
          lightek_social_circles: {
            owner_profile_id:
              profile.id
          }
        )
    end
  end
end
