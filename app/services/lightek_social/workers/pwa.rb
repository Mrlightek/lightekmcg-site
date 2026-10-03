# frozen_string_literal: true

module LightekSocial
  module Workers
    class Pwa
      DEFAULT_LIMIT = 30
      MAX_LIMIT = 50

      def self.perform(action, payload = {})
        new(
          action: action,
          payload: payload
        ).perform
      end

      def initialize(action:, payload:)
        @action =
          action.to_s

        @payload =
          payload
            .to_h
            .deep_stringify_keys
      end

      def perform
        case action
        when "people_recommend"
          people_recommend

        when "relationship_context"
          relationship_context

        when "connection_opportunities"
          connection_opportunities

        when "follow"
          follow

        when "friendship_request"
          friendship_request

        when "friendship_respond"
          friendship_respond

        when "friendship_end"
          friendship_end

        when "block"
          block

        else
          raise ArgumentError,
                "Unsupported Social action: #{action}"
        end
      end

      private

      attr_reader :action,
                  :payload

      def user
        @user ||=
          User.find(
            payload.fetch(
              "user_id"
            )
          )
      end

      def profile
        @profile ||=
          user.profile ||
          raise(
            LightekSocial::AccessDenied,
            "A Lightek profile is required for Social"
          )
      end

      def target_profile
        @target_profile ||=
          Profile.find(
            payload.fetch(
              "profile_id"
            )
          )
      end

      def friendship
        @friendship ||=
          Friendship.find(
            payload.fetch(
              "friendship_id"
            )
          )
      end

      def limit
        requested =
          payload
            .fetch(
              "limit",
              DEFAULT_LIMIT
            )
            .to_i

        [
          [
            requested,
            1
          ].max,
          MAX_LIMIT
        ].min
      end

      def people_recommend
        recommendations =
          PeopleRecommendation.call(
            profile:
              profile,

            query:
              payload["query"],

            limit:
              limit
          )

        {
          "recommendations" =>
            recommendations.map do |record|
              record.deep_stringify_keys
            end
        }
      end

      def relationship_context
        {
          "relationship" =>
            relationship_payload(
              target_profile
            )
        }
      end

      def connection_opportunities
        records =
          ConnectionOpportunity
            .where(
              profile_id:
                profile.id,

              status:
                "pending"
            )
            .where(
              "expires_at IS NULL OR expires_at > ?",
              Time.current
            )
            .includes(
              :related_profile
            )
            .order(
              detected_at: :desc,
              id: :desc
            )
            .limit(
              limit
            )

        visible =
          records.reject do |record|
            LightekSocial.blocked_between?(
              profile,
              record.related_profile
            )
          end

        {
          "opportunities" =>
            visible.map do |record|
              opportunity_payload(
                record
              )
            end
        }
      end

      def follow
        record =
          FollowProfile.call(
            follower_profile:
              profile,

            followed_profile:
              target_profile
          )

        {
          "follow" =>
            follow_payload(
              record
            ),

          "relationship" =>
            relationship_payload(
              target_profile
            )
        }
      end

      def friendship_request
        record =
          RequestFriendship.call(
            requester_profile:
              profile,

            addressee_profile:
              target_profile
          )

        {
          "friendship" =>
            friendship_payload(
              record
            ),

          "relationship" =>
            relationship_payload(
              target_profile
            )
        }
      end

      def friendship_respond
        record =
          friendship

        other =
          record.other_profile_for(
            profile
          )

        raise LightekSocial::AccessDenied,
              "profile is not part of friendship" \
          unless other

        result =
          RespondToFriendship.call(
            friendship:
              record,

            actor_profile:
              profile,

            action:
              payload.fetch(
                "action"
              )
          )

        {
          "friendship" =>
            friendship_payload(
              result
            ),

          "relationship" =>
            relationship_payload(
              other
            )
        }
      end

      def friendship_end
        record =
          friendship

        other =
          record.other_profile_for(
            profile
          )

        raise LightekSocial::AccessDenied,
              "profile is not part of friendship" \
          unless other

        result =
          EndFriendship.call(
            friendship:
              record,

            actor_profile:
              profile
          )

        {
          "friendship" =>
            friendship_payload(
              result
            ),

          "relationship" =>
            relationship_payload(
              other
            )
        }
      end

      def block
        record =
          BlockProfile.call(
            blocker_profile:
              profile,

            blocked_profile:
              target_profile,

            reason_code:
              payload["reason_code"]
          )

        {
          "block" =>
            block_payload(
              record
            ),

          "profile" =>
            profile_payload(
              target_profile
            )
        }
      end

      def relationship_payload(other)
        if LightekSocial.blocked_between?(
          profile,
          other
        )
          raise LightekSocial::AccessDenied,
                "blocked relationship"
        end

        graph =
          Graph.new(
            profile:
              profile
          )

        mutual_ids =
          graph.mutual_ids_with(
            other
          )

        mutuals =
          Profile
            .where(
              id:
                mutual_ids.to_a
            )
            .order(
              :display_name,
              :handle,
              :id
            )
            .limit(20)
            .map do |record|
              profile_payload(
                record
              )
            end

        friendship_record =
          Friendship.find_by(
            pair_key:
              LightekSocial.pair_key(
                profile,
                other
              )
          )

        strength =
          RelationshipStrength.find_by(
            pair_key:
              LightekSocial.pair_key(
                profile,
                other
              )
          )

        friend =
          graph.accepted_friend?(
            other
          )

        following =
          graph.following?(
            other
          )

        follows_you =
          graph.follows_you?(
            other
          )

        degree =
          graph.degree_to(
            other,
            max_depth: 3
          )

        {
          "profile" =>
            profile_payload(
              other
            ),

          "degree" =>
            degree,

          "mutual_count" =>
            mutual_ids.length,

          "mutuals" =>
            mutuals,

          "following" =>
            following,

          "follows_you" =>
            follows_you,

          "friend" =>
            friend,

          "friendship" =>
            friendship_record &&
            friendship_payload(
              friendship_record,
              viewer:
                profile
            ),

          "strength" =>
            strength &&
            strength_payload(
              strength
            ),

          "reasons" =>
            relationship_reasons(
              friend:
                friend,

              following:
                following,

              follows_you:
                follows_you,

              mutual_count:
                mutual_ids.length,

              degree:
                degree
            )
        }
      end

      def relationship_reasons(
        friend:,
        following:,
        follows_you:,
        mutual_count:,
        degree:
      )
        reasons = []

        reasons <<
          "Friend" if friend

        if following &&
           follows_you
          reasons <<
            "You follow each other"
        elsif following
          reasons <<
            "You follow them"
        elsif follows_you
          reasons <<
            "They follow you"
        end

        if mutual_count.positive?
          label =
            mutual_count == 1 ?
              "connection" :
              "connections"

          reasons <<
            "#{mutual_count} mutual #{label}"
        end

        if degree &&
           degree > 1
          reasons <<
            "#{degree}-degree connection"
        end

        reasons
      end

      def profile_payload(record)
        {
          "id" =>
            record.id,

          "name" =>
            record.public_display_name,

          "display_handle" =>
            record.display_handle,

          "avatar_url" =>
            record.avatar_url,

          "profile_type" =>
            record.profile_type
        }
      end

      def follow_payload(record)
        {
          "id" =>
            record.id,

          "follower_profile_id" =>
            record.follower_profile_id,

          "followed_profile_id" =>
            record.followed_profile_id,

          "created_at" =>
            record
              .created_at
              .iso8601
        }
      end

      def friendship_payload(
        record,
        viewer: profile
      )
        direction =
          if record.requester_profile_id ==
             viewer.id
            "outgoing"
          elsif record.addressee_profile_id ==
                viewer.id
            "incoming"
          end

        {
          "id" =>
            record.id,

          "requester_profile_id" =>
            record.requester_profile_id,

          "addressee_profile_id" =>
            record.addressee_profile_id,

          "status" =>
            record.status,

          "direction" =>
            direction,

          "responded_at" =>
            record
              .responded_at
              &.iso8601,

          "accepted_at" =>
            record
              .accepted_at
              &.iso8601,

          "ended_at" =>
            record
              .ended_at
              &.iso8601,

          "created_at" =>
            record
              .created_at
              .iso8601,

          "updated_at" =>
            record
              .updated_at
              .iso8601
        }
      end

      def strength_payload(record)
        {
          "reciprocity" =>
            record.reciprocity.to_f,

          "continuity" =>
            record.continuity.to_f,

          "context_diversity" =>
            record.context_diversity.to_f,

          "shared_experience" =>
            record.shared_experience.to_f,

          "recency" =>
            record.recency.to_f,

          "confidence" =>
            record.confidence.to_f,

          "evidence_count" =>
            record.observed_event_count,

          "calculated_at" =>
            record
              .computed_at
              &.iso8601
        }
      end

      def opportunity_payload(record)
        metadata =
          record
            .metadata
            .to_h

        {
          "id" =>
            record.id,

          "kind" =>
            record.kind,

          "status" =>
            record.status,

          "reason_code" =>
            record.reason_code,

          "reasons" =>
            Array(
              metadata[
                "reasons"
              ]
            ),

          "related_profile" =>
            profile_payload(
              record.related_profile
            ),

          "detected_at" =>
            record
              .detected_at
              &.iso8601,

          "expires_at" =>
            record
              .expires_at
              &.iso8601
        }
      end

      def block_payload(record)
        {
          "id" =>
            record.id,

          "blocker_profile_id" =>
            record.blocker_profile_id,

          "blocked_profile_id" =>
            record.blocked_profile_id,

          "reason_code" =>
            record.reason_code,

          "created_at" =>
            record
              .created_at
              .iso8601
        }
      end
    end
  end
end
