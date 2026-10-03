# frozen_string_literal: true

module LightekSocial
  class RelationshipStrengthCalculator
    SHARED_EXPERIENCE_PREFIXES =
      %w[
        community.
        event.
        collaboration.
        conversation.sustained
        content.discussed
      ].freeze

    def self.call(left, right)
      new(
        left,
        right
      ).call
    end

    def initialize(left, right)
      @profile_a_id,
      @profile_b_id =
        LightekSocial.pair_ids(
          left,
          right
        )

      @pair_key =
        "#{profile_a_id}:" \
        "#{profile_b_id}"
    end

    def call
      events =
        RelationshipEvent
          .strength_signals
          .where(
            pair_key:
              pair_key
          )
          .order(
            :occurred_at,
            :id
          )
          .to_a

      values =
        calculate(
          events
        )

      record =
        RelationshipStrength
          .find_or_initialize_by(
            pair_key:
              pair_key
          )

      record.assign_attributes(
        profile_a_id:
          profile_a_id,

        profile_b_id:
          profile_b_id,

        **values,

        computed_at:
          Time.current
      )

      record.save!

      record
    end

    private

    attr_reader :profile_a_id,
                :profile_b_id,
                :pair_key

    def calculate(events)
      return empty_values if
        events.empty?

      first_at =
        events.first.occurred_at

      last_at =
        events.last.occurred_at

      actor_counts =
        events
          .group_by(
            &:actor_profile_id
          )
          .transform_values(
            &:count
          )

      left_count =
        actor_counts.fetch(
          profile_a_id,
          0
        )

      right_count =
        actor_counts.fetch(
          profile_b_id,
          0
        )

      reciprocity =
        if left_count.positive? &&
           right_count.positive?
          [
            left_count,
            right_count
          ].min.to_f /
            [
              left_count,
              right_count
            ].max
        else
          0.0
        end

      span_days =
        [
          (
            (
              last_at -
              first_at
            ) /
            1.day
          ),
          0
        ].max

      continuity =
        if events.length < 2
          0.0
        else
          [
            span_days /
              180.0,
            1.0
          ].min
        end

      contexts =
        events.map do |event|
          event.context_type.presence ||
            event.event_type
              .split(".")
              .first
        end.compact.uniq

      context_diversity =
        [
          contexts.length /
            5.0,
          1.0
        ].min

      shared_count =
        events.count do |event|
          SHARED_EXPERIENCE_PREFIXES.any? do |prefix|
            event.event_type.start_with?(
              prefix
            )
          end
        end

      shared_experience =
        [
          shared_count /
            8.0,
          1.0
        ].min

      days_since =
        [
          (
            (
              Time.current -
              last_at
            ) /
            1.day
          ),
          0
        ].max

      recency =
        1.0 /
        (
          1.0 +
          (
            days_since /
            30.0
          )
        )

      confidence =
        [
          events.length /
            20.0,
          1.0
        ].min *
        (
          0.5 +
          (
            context_diversity *
            0.5
          )
        )

      {
        reciprocity:
          bounded(
            reciprocity
          ),

        continuity:
          bounded(
            continuity
          ),

        context_diversity:
          bounded(
            context_diversity
          ),

        shared_experience:
          bounded(
            shared_experience
          ),

        recency:
          bounded(
            recency
          ),

        confidence:
          bounded(
            confidence
          ),

        observed_event_count:
          events.length,

        first_observed_at:
          first_at,

        last_observed_at:
          last_at,

        metadata: {
          "signal_event_types" =>
            events
              .map(
                &:event_type
              )
              .uniq
        }
      }
    end

    def empty_values
      {
        reciprocity: 0,
        continuity: 0,
        context_diversity: 0,
        shared_experience: 0,
        recency: 0,
        confidence: 0,
        observed_event_count: 0,
        first_observed_at: nil,
        last_observed_at: nil,
        metadata: {}
      }
    end

    def bounded(value)
      [
        [
          value.to_f,
          0.0
        ].max,
        1.0
      ].min.round(4)
    end
  end
end
