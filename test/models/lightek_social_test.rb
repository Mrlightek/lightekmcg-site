# frozen_string_literal: true

require "test_helper"

class LightekSocialTest <
      ActiveSupport::TestCase

  def setup
    @alice =
      create_user(
        "alice"
      )

    @bob =
      create_user(
        "bob"
      )

    @carol =
      create_user(
        "carol"
      )

    @dave =
      create_user(
        "dave"
      )
  end

  test "follow is directional and cannot target self" do
    follow =
      LightekSocial::
        FollowProfile.call(
          follower_profile:
            @alice.profile,

          followed_profile:
            @bob.profile
        )

    assert_equal(
      @alice.profile,
      follow.follower_profile
    )

    assert_equal(
      @bob.profile,
      follow.followed_profile
    )

    invalid =
      LightekSocial::
        Follow.new(
          follower_profile:
            @alice.profile,

          followed_profile:
            @alice.profile
        )

    assert_not(
      invalid.valid?
    )
  end

  test "friendship requires explicit acceptance" do
    friendship =
      LightekSocial::
        RequestFriendship.call(
          requester_profile:
            @alice.profile,

          addressee_profile:
            @bob.profile
        )

    assert_equal(
      "pending",
      friendship.status
    )

    LightekSocial::
      RespondToFriendship.call(
        friendship:
          friendship,

        actor_profile:
          @bob.profile,

        action:
          "accept"
      )

    assert_equal(
      "accepted",
      friendship.reload.status
    )

    assert_not_nil(
      friendship.accepted_at
    )
  end

  test "reciprocal friendship requests become accepted" do
    friendship =
      LightekSocial::
        RequestFriendship.call(
          requester_profile:
            @alice.profile,

          addressee_profile:
            @bob.profile
        )

    second =
      LightekSocial::
        RequestFriendship.call(
          requester_profile:
            @bob.profile,

          addressee_profile:
            @alice.profile
        )

    assert_equal(
      friendship.id,
      second.id
    )

    assert_equal(
      "accepted",
      second.status
    )
  end

  test "circle carries human-defined meaning" do
    circle =
      LightekSocial::
        Circle.create!(
          owner_profile:
            @alice.profile,

          name:
            "Creative Circle"
        )

    membership =
      circle.memberships.create!(
        profile:
          @bob.profile
      )

    assert_equal(
      @bob.profile,
      membership.profile
    )

    own_membership =
      circle.memberships.build(
        profile:
          @alice.profile
      )

    assert_not(
      own_membership.valid?
    )
  end

  test "block is a hard graph boundary" do
    LightekSocial::
      FollowProfile.call(
        follower_profile:
          @alice.profile,

        followed_profile:
          @bob.profile
      )

    LightekSocial::
      FollowProfile.call(
        follower_profile:
          @bob.profile,

        followed_profile:
          @alice.profile
      )

    graph =
      LightekSocial::
        Graph.new(
          profile:
            @alice.profile
        )

    assert_equal(
      1,
      graph.degree_to(
        @bob.profile
      )
    )

    LightekSocial::
      BlockProfile.call(
        blocker_profile:
          @alice.profile,

        blocked_profile:
          @bob.profile
      )

    assert_nil(
      graph.degree_to(
        @bob.profile
      )
    )

    assert_not(
      LightekSocial::
        Follow.exists?(
          follower_profile:
            @alice.profile,

          followed_profile:
            @bob.profile
        )
    )
  end

  test "graph calculates meaningful degrees of separation" do
    friendship =
      LightekSocial::
        RequestFriendship.call(
          requester_profile:
            @alice.profile,

          addressee_profile:
            @bob.profile
        )

    LightekSocial::
      RespondToFriendship.call(
        friendship:
          friendship,

        actor_profile:
          @bob.profile,

        action:
          "accept"
      )

    LightekSocial::
      FollowProfile.call(
        follower_profile:
          @bob.profile,

        followed_profile:
          @carol.profile
      )

    LightekSocial::
      FollowProfile.call(
        follower_profile:
          @carol.profile,

        followed_profile:
          @bob.profile
      )

    graph =
      LightekSocial::
        Graph.new(
          profile:
            @alice.profile
        )

    assert_equal(
      1,
      graph.degree_to(
        @bob.profile
      )
    )

    assert_equal(
      2,
      graph.degree_to(
        @carol.profile
      )
    )

    assert_equal(
      [
        @alice.profile.id,
        @bob.profile.id,
        @carol.profile.id
      ],
      graph.shortest_path_to(
        @carol.profile
      )
    )
  end

  private

  def create_user(prefix)
    User.create!(
      email_address:
        "#{prefix}-" \
        "#{SecureRandom.hex(5)}" \
        "@example.test",

      password:
        "Password123!",

      first_name:
        prefix.capitalize,

      last_name:
        "Social",

      role:
        "client"
    )
  end
end
