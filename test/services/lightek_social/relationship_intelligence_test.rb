# frozen_string_literal: true

require "test_helper"

class LightekSocialRelationshipIntelligenceTest <
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
  end

  test "relationship strength derives from factual events" do
    LightekSocial::
      RecordRelationshipEvent.call(
        actor_profile:
          @alice.profile,

        target_profile:
          @bob.profile,

        event_type:
          "conversation.sustained",

        occurred_at:
          90.days.ago,

        source_key:
          "test-strength-1"
      )

    LightekSocial::
      RecordRelationshipEvent.call(
        actor_profile:
          @bob.profile,

        target_profile:
          @alice.profile,

        event_type:
          "community.contributed_together",

        occurred_at:
          30.days.ago,

        source_key:
          "test-strength-2"
      )

    LightekSocial::
      RecordRelationshipEvent.call(
        actor_profile:
          @alice.profile,

        target_profile:
          @bob.profile,

        event_type:
          "event.attended_together",

        occurred_at:
          2.days.ago,

        source_key:
          "test-strength-3"
      )

    strength =
      LightekSocial::
        RelationshipStrengthCalculator.call(
          @alice.profile,
          @bob.profile
        )

    assert_equal(
      3,
      strength.observed_event_count
    )

    assert_operator(
      strength.reciprocity.to_f,
      :>,
      0
    )

    assert_operator(
      strength.continuity.to_f,
      :>,
      0
    )

    assert_operator(
      strength.shared_experience.to_f,
      :>,
      0
    )

    assert_operator(
      strength.confidence.to_f,
      :>,
      0
    )
  end

  test "people recommendation explains why someone appears" do
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

    results =
      LightekSocial::
        PeopleRecommendation.call(
          profile:
            @alice.profile
        )

    bob =
      results.find do |record|
        record.dig(
          :profile,
          :id
        ) ==
          @bob.profile.id
      end

    assert_not_nil(
      bob
    )

    assert_equal(
      true,
      bob.dig(
        :relationship,
        :friend
      )
    )

    assert_includes(
      bob.dig(
        :recommendation,
        :reasons
      ),
      "Friend"
    )
  end

  test "blocked profiles never appear in recommendations" do
    LightekSocial::
      BlockProfile.call(
        blocker_profile:
          @alice.profile,

        blocked_profile:
          @bob.profile
      )

    results =
      LightekSocial::
        PeopleRecommendation.call(
          profile:
            @alice.profile
        )

    ids =
      results.map do |record|
        record.dig(
          :profile,
          :id
        )
      end

    assert_not_includes(
      ids,
      @bob.profile.id
    )
  end

  test "connection opportunities require meaningful existing relationship" do
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

    opportunity =
      LightekSocial::
        ConnectionOpportunityBuilder.call(
          profile:
            @alice.profile,

          related_profile:
            @bob.profile,

          kind:
            "shared_event",

          reasons: [
            "You both usually connect around documentary events"
          ],

          source_key:
            "test-opportunity-1"
        )

    assert_equal(
      "pending",
      opportunity.status
    )

    assert_equal(
      [
        "You both usually connect around documentary events"
      ],
      opportunity.reasons
    )

    assert_raises(
      LightekSocial::
        AccessDenied
    ) do
      LightekSocial::
        ConnectionOpportunityBuilder.call(
          profile:
            @alice.profile,

          related_profile:
            @carol.profile,

          kind:
            "shared_event",

          reasons: [
            "No actual relationship"
          ]
        )
    end
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
        "Graph",

      role:
        "client"
    )
  end
end
