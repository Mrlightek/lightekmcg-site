# frozen_string_literal: true

require "test_helper"

class LightekSocialPwaWorkerTest <
      ActiveSupport::TestCase

  setup do
    @alice =
      create_profile(
        "Alice"
      )

    @bob =
      create_profile(
        "Bob"
      )

    @carol =
      create_profile(
        "Carol"
      )
  end

  test "people recommendations use authenticated profile and exclude self" do
    request =
      LightekSocial::RequestFriendship.call(
        requester_profile:
          @alice,

        addressee_profile:
          @bob
      )

    LightekSocial::RespondToFriendship.call(
      friendship:
        request,

      actor_profile:
        @bob,

      action:
        "accept"
    )

    result =
      perform_as(
        @alice,
        "people_recommend"
      )

    recommendations =
      result.fetch(
        "recommendations"
      )

    ids =
      recommendations.map do |record|
        record
          .fetch(
            "profile"
          )
          .fetch(
            "id"
          )
      end

    assert_includes(
      ids,
      @bob.id
    )

    refute_includes(
      ids,
      @alice.id
    )

    bob =
      recommendations.find do |record|
        record.dig(
          "profile",
          "id"
        ) == @bob.id
      end

    assert(
      Array(
        bob.dig(
          "recommendation",
          "reasons"
        )
      ).any?
    )
  end

  test "relationship context exposes dimensions without universal friendship score" do
    request =
      LightekSocial::RequestFriendship.call(
        requester_profile:
          @alice,

        addressee_profile:
          @bob
      )

    LightekSocial::RespondToFriendship.call(
      friendship:
        request,

      actor_profile:
        @bob,

      action:
        "accept"
    )

    result =
      perform_as(
        @alice,
        "relationship_context",
        "profile_id" =>
          @bob.id
      )

    relationship =
      result.fetch(
        "relationship"
      )

    assert_equal(
      true,
      relationship.fetch(
        "friend"
      )
    )

    assert_equal(
      1,
      relationship.fetch(
        "degree"
      )
    )

    assert_includes(
      relationship.fetch(
        "reasons"
      ),
      "Friend"
    )

    refute(
      relationship.key?(
        "score"
      )
    )

    strength =
      relationship.fetch(
        "strength"
      )

    assert(
      strength.key?(
        "reciprocity"
      )
    )

    refute(
      strength.key?(
        "overall_score"
      )
    )
  end

  test "follow actor is derived from authenticated user" do
    result =
      perform_as(
        @alice,
        "follow",
        "profile_id" =>
          @bob.id,

        "follower_profile_id" =>
          @carol.id
      )

    assert_equal(
      @alice.id,
      result
        .fetch(
          "follow"
        )
        .fetch(
          "follower_profile_id"
        )
    )

    assert(
      LightekSocial::Follow.exists?(
        follower_profile_id:
          @alice.id,

        followed_profile_id:
          @bob.id
      )
    )

    refute(
      LightekSocial::Follow.exists?(
        follower_profile_id:
          @carol.id,

        followed_profile_id:
          @bob.id
      )
    )
  end

  test "friendship lifecycle is explicit and actor scoped" do
    requested =
      perform_as(
        @alice,
        "friendship_request",
        "profile_id" =>
          @bob.id
      )

    friendship_id =
      requested
        .fetch(
          "friendship"
        )
        .fetch(
          "id"
        )

    assert_equal(
      "pending",
      requested
        .fetch(
          "friendship"
        )
        .fetch(
          "status"
        )
    )

    accepted =
      perform_as(
        @bob,
        "friendship_respond",
        "friendship_id" =>
          friendship_id,

        "action" =>
          "accept"
      )

    assert_equal(
      "accepted",
      accepted
        .fetch(
          "friendship"
        )
        .fetch(
          "status"
        )
    )

    ended =
      perform_as(
        @alice,
        "friendship_end",
        "friendship_id" =>
          friendship_id
      )

    assert_equal(
      "ended",
      ended
        .fetch(
          "friendship"
        )
        .fetch(
          "status"
        )
    )
  end

  test "connection opportunities are private to authenticated profile" do
    friendship =
      LightekSocial::RequestFriendship.call(
        requester_profile:
          @alice,

        addressee_profile:
          @bob
      )

    LightekSocial::RespondToFriendship.call(
      friendship:
        friendship,

      actor_profile:
        @bob,

      action:
        "accept"
    )

    opportunity =
      LightekSocial::ConnectionOpportunityBuilder.call(
        profile:
          @alice,

        related_profile:
          @bob,

        kind:
          "reconnect",

        reasons: [
          "A relevant shared experience exists"
        ],

        source_key:
          "test-opportunity-" +
          SecureRandom.hex(4)
      )

    alice_result =
      perform_as(
        @alice,
        "connection_opportunities"
      )

    alice_ids =
      alice_result
        .fetch(
          "opportunities"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    assert_includes(
      alice_ids,
      opportunity.id
    )

    bob_result =
      perform_as(
        @bob,
        "connection_opportunities"
      )

    bob_ids =
      bob_result
        .fetch(
          "opportunities"
        )
        .map do |record|
          record.fetch(
            "id"
          )
        end

    refute_includes(
      bob_ids,
      opportunity.id
    )
  end

  test "block is a hard actor-derived relationship boundary" do
    LightekSocial::FollowProfile.call(
      follower_profile:
        @alice,

      followed_profile:
        @bob
    )

    LightekSocial::FollowProfile.call(
      follower_profile:
        @bob,

      followed_profile:
        @alice
    )

    result =
      perform_as(
        @alice,
        "block",
        "profile_id" =>
          @bob.id,

        "blocker_profile_id" =>
          @carol.id,

        "reason_code" =>
          "user_choice"
      )

    assert_equal(
      @alice.id,
      result
        .fetch(
          "block"
        )
        .fetch(
          "blocker_profile_id"
        )
    )

    assert(
      LightekSocial::Block.exists?(
        blocker_profile_id:
          @alice.id,

        blocked_profile_id:
          @bob.id
      )
    )

    refute(
      LightekSocial::Follow.exists?(
        follower_profile_id: [
          @alice.id,
          @bob.id
        ],

        followed_profile_id: [
          @alice.id,
          @bob.id
        ]
      )
    )
  end

  private

  def perform_as(
    actor_profile,
    action,
    extra = {}
  )
    LightekSocial::Workers::Pwa.perform(
      action,
      {
        "user_id" =>
          actor_profile.user_id
      }.merge(
        extra
      )
    )
  end

  def create_profile(label)
    token =
      SecureRandom.hex(
        5
      )

    user =
      User.create!(
        email_address:
          "#{label.downcase}-#{token}@example.test",

        password:
          "Password123!",

        first_name:
          label,

        last_name:
          "Social",

        role:
          "client"
      )

    user.profile.update!(
      display_name:
        "#{label} Social"
    )

    user.profile
  end
end
