# frozen_string_literal: true

require "set"

module LightekSocial
  class PeopleRecommendation
    DEFAULT_LIMIT = 30

    def self.call(...)
      new(...).call
    end

    def initialize(
      profile:,
      query: nil,
      limit: DEFAULT_LIMIT
    )
      @profile =
        profile

      @query =
        query
          .to_s
          .strip

      @limit =
        [
          limit.to_i,
          1
        ].max

      @graph =
        Graph.new(
          profile:
            profile
        )
    end

    def call
      candidates
        .map do |candidate|
          recommendation_for(
            candidate
          )
        end
        .sort_by do |record|
          [
            -record.dig(
              :recommendation,
              :score
            ),

            record.dig(
              :profile,
              :name
            ).to_s.downcase,

            record.dig(
              :profile,
              :id
            )
          ]
        end
        .first(
          limit
        )
    end

    private

    attr_reader :profile,
                :query,
                :limit,
                :graph

    def candidates
      scope =
        Profile.where.not(
          id:
            [
              profile.id
            ] +
            blocked_profile_ids
        )

      if query.present?
        normalized =
          query
            .delete_prefix("@")
            .downcase

        pattern =
          "%" +
          ActiveRecord::Base
            .sanitize_sql_like(
              normalized
            ) +
          "%"

        return scope
          .where(
            "LOWER(COALESCE(display_name, '')) LIKE :pattern " \
            "OR LOWER(handle) LIKE :pattern",
            pattern:
              pattern
          )
          .limit(
            limit * 4
          )
          .to_a
      end

      network_ids =
        network_candidate_ids

      network =
        scope.where(
          id:
            network_ids
        ).to_a

      remaining =
        [
          (
            limit * 3
          ) -
          network.length,
          0
        ].max

      fallback =
        scope
          .where.not(
            id:
              network_ids
          )
          .order(
            :display_name,
            :handle,
            :id
          )
          .limit(
            remaining
          )
          .to_a

      network +
        fallback
    end

    def network_candidate_ids
      first =
        graph.connection_ids(
          profile.id
        ).to_a

      second =
        first.flat_map do |id|
          graph.connection_ids(
            id
          ).to_a
        end

      third =
        second.flat_map do |id|
          graph.connection_ids(
            id
          ).to_a
        end

      (
        first +
        second +
        third
      )
        .uniq
        .reject do |id|
          id ==
            profile.id
        end
    end

    def recommendation_for(
      candidate
    )
      friend =
        graph.accepted_friend?(
          candidate
        )

      following =
        graph.following?(
          candidate
        )

      follows_you =
        graph.follows_you?(
          candidate
        )

      mutual_ids =
        graph.mutual_ids_with(
          candidate
        )

      degree =
        graph.degree_to(
          candidate,
          max_depth:
            3
        )

      talked =
        conversation_profile_ids
          .include?(
            candidate.id
          )

      strength =
        RelationshipStrength.find_by(
          pair_key:
            LightekSocial.pair_key(
              profile,
              candidate
            )
        )

      score = 0.0
      reasons = []

      if friend
        score += 100
        reasons << "Friend"
      end

      if following &&
         follows_you
        score += 130
        reasons << "Mutual follow"
      else
        if following
          score += 70
          reasons << "You follow this person"
        end

        if follows_you
          score += 60
          reasons << "Follows you"
        end
      end

      if talked
        score += 55
        reasons << "You've talked before"
      end

      if mutual_ids.any?
        count =
          mutual_ids.length

        score += [
          count,
          5
        ].min * 20

        reasons <<
          "#{count} mutual " \
          "#{count == 1 ? 'connection' : 'connections'}"
      end

      if degree &&
         degree > 1
        score +=
          case degree
          when 2
            15
          when 3
            5
          else
            0
          end

        reasons <<
          "#{degree}° connection"
      end

      if strength &&
         strength.confidence.to_f >
           0
        score +=
          strength.overall *
          40

        if strength.confidence.to_f >=
             0.25
          reasons <<
            "Established relationship history"
        end
      end

      score +=
        search_relevance(
          candidate
        )

      {
        profile: {
          id:
            candidate.id,

          name:
            candidate.public_display_name,

          display_handle:
            candidate.display_handle,

          avatar_url:
            candidate.avatar_url,

          profile_type:
            candidate.profile_type
        },

        relationship: {
          degree:
            degree,

          mutual_count:
            mutual_ids.length,

          friend:
            friend,

          following:
            following,

          follows_you:
            follows_you,

          prior_conversation:
            talked
        },

        recommendation: {
          score:
            score.round(4),

          reasons:
            reasons
        }
      }
    end

    def search_relevance(
      candidate
    )
      return 0 if query.blank?

      needle =
        query
          .delete_prefix("@")
          .downcase

      handle =
        candidate
          .handle
          .to_s
          .downcase

      name =
        candidate
          .public_display_name
          .to_s
          .downcase

      return 1000 if
        handle ==
          needle

      return 800 if
        name ==
          needle

      return 600 if
        handle.start_with?(
          needle
        )

      return 500 if
        name.start_with?(
          needle
        )

      250
    end

    def blocked_profile_ids
      outgoing =
        Block.where(
          blocker_profile_id:
            profile.id
        ).pluck(
          :blocked_profile_id
        )

      incoming =
        Block.where(
          blocked_profile_id:
            profile.id
        ).pluck(
          :blocker_profile_id
        )

      (
        outgoing +
        incoming
      ).uniq
    end

    def conversation_profile_ids
      @conversation_profile_ids ||=
        begin
          own_conversation_ids =
            LightekMessaging::
              Participant
                .where(
                  profile_id:
                    profile.id,
                  left_at:
                    nil
                )
                .pluck(
                  :conversation_id
                )

          direct_ids =
            LightekMessaging::
              Conversation
                .where(
                  id:
                    own_conversation_ids,
                  kind:
                    "direct"
                )
                .pluck(
                  :id
                )

          LightekMessaging::
            Participant
              .where(
                conversation_id:
                  direct_ids,
                left_at:
                  nil
              )
              .where.not(
                profile_id:
                  profile.id
              )
              .pluck(
                :profile_id
              )
              .to_set
        end
    end
  end
end
