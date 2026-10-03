# frozen_string_literal: true

require "set"

module LightekSocial
  class Graph
    DEFAULT_MAX_DEPTH = 3

    def initialize(profile:)
      @profile =
        profile
    end

    attr_reader :profile

    def connection_ids(
      profile_id =
        profile.id
    )
      ids =
        accepted_friend_ids(
          profile_id
        ) |
        mutual_follow_ids(
          profile_id
        )

      ids -
        blocked_ids_for(
          profile_id
        )
    end

    def mutual_ids_with(other)
      left =
        connection_ids(
          profile.id
        )

      right =
        connection_ids(
          LightekSocial.profile_id(
            other
          )
        )

      left & right
    end

    def mutuals_with(other)
      Profile.where(
        id:
          mutual_ids_with(
            other
          )
      ).order(
        :display_name,
        :handle,
        :id
      )
    end

    def degree_to(
      other,
      max_depth:
        DEFAULT_MAX_DEPTH
    )
      path =
        shortest_path_to(
          other,
          max_depth:
            max_depth
        )

      return nil unless path

      path.length - 1
    end

    def shortest_path_to(
      other,
      max_depth:
        DEFAULT_MAX_DEPTH
    )
      source_id =
        profile.id

      target_id =
        LightekSocial.profile_id(
          other
        )

      return [
        source_id
      ] if source_id ==
             target_id

      return nil if
        blocked_ids_for(
          source_id
        ).include?(
          target_id
        )

      queue = [
        [
          source_id,
          [
            source_id
          ]
        ]
      ]

      visited =
        Set.new(
          [
            source_id
          ]
        )

      until queue.empty?
        node_id,
        path =
          queue.shift

        depth =
          path.length - 1

        next if depth >=
                max_depth

        connection_ids(
          node_id
        ).each do |neighbor_id|
          next if visited.include?(
            neighbor_id
          )

          next_path =
            path +
            [
              neighbor_id
            ]

          return next_path if
            neighbor_id ==
              target_id

          visited.add(
            neighbor_id
          )

          queue << [
            neighbor_id,
            next_path
          ]
        end
      end

      nil
    end

    def accepted_friend?(
      other
    )
      Friendship.accepted.exists?(
        pair_key:
          LightekSocial.pair_key(
            profile,
            other
          )
      )
    end

    def following?(
      other
    )
      Follow.exists?(
        follower_profile_id:
          profile.id,

        followed_profile_id:
          LightekSocial.profile_id(
            other
          )
      )
    end

    def follows_you?(
      other
    )
      Follow.exists?(
        follower_profile_id:
          LightekSocial.profile_id(
            other
          ),

        followed_profile_id:
          profile.id
      )
    end

    private

    def accepted_friend_ids(
      profile_id
    )
      rows =
        Friendship.accepted
          .where(
            requester_profile_id:
              profile_id
          )
          .or(
            Friendship.accepted.where(
              addressee_profile_id:
                profile_id
            )
          )
          .pluck(
            :requester_profile_id,
            :addressee_profile_id
          )

      rows.map do |left, right|
        left == profile_id ?
          right :
          left
      end.to_set
    end

    def mutual_follow_ids(
      profile_id
    )
      outgoing =
        Follow.where(
          follower_profile_id:
            profile_id
        ).pluck(
          :followed_profile_id
        ).to_set

      incoming =
        Follow.where(
          followed_profile_id:
            profile_id
        ).pluck(
          :follower_profile_id
        ).to_set

      outgoing &
        incoming
    end

    def blocked_ids_for(
      profile_id
    )
      outgoing =
        Block.where(
          blocker_profile_id:
            profile_id
        ).pluck(
          :blocked_profile_id
        )

      incoming =
        Block.where(
          blocked_profile_id:
            profile_id
        ).pluck(
          :blocker_profile_id
        )

      (
        outgoing +
        incoming
      ).to_set
    end
  end
end
