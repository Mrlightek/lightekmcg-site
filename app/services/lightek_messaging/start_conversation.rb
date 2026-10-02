# frozen_string_literal: true

module LightekMessaging
  class StartConversation
    SUPPORTED_KINDS =
      %w[
        direct
        group
      ].freeze

    def self.call(
      creator_profile:,
      participant_profile_ids:,
      kind:,
      title: nil
    )
      new(
        creator_profile: creator_profile,
        participant_profile_ids:
          participant_profile_ids,
        kind: kind,
        title: title
      ).call
    end

    def initialize(
      creator_profile:,
      participant_profile_ids:,
      kind:,
      title:
    )
      @creator_profile =
        creator_profile

      @participant_profile_ids =
        Array(
          participant_profile_ids
        )
          .map(&:to_i)

      @kind =
        kind.to_s

      @title =
        title.to_s.strip
    end

    def call
      validate_kind!

      ids =
        (
          participant_profile_ids +
          [creator_profile.id]
        )
          .uniq
          .sort

      validate_participant_count!(
        ids
      )

      profiles =
        Profile
          .where(id: ids)
          .index_by(&:id)

      missing =
        ids -
        profiles.keys

      if missing.any?
        raise ArgumentError,
              "Unknown profile ids: " \
              "#{missing.join(', ')}"
      end

      if kind == "direct"
        start_direct(
          ids,
          profiles
        )
      else
        start_group(
          ids,
          profiles
        )
      end
    end

    private

    attr_reader :creator_profile,
                :participant_profile_ids,
                :kind,
                :title

    def validate_kind!
      return if SUPPORTED_KINDS.include?(
        kind
      )

      raise ArgumentError,
            "Unsupported conversation kind: " \
            "#{kind.inspect}"
    end

    def validate_participant_count!(ids)
      case kind
      when "direct"
        return if ids.length == 2

        raise ArgumentError,
              "Direct conversations require " \
              "exactly two participants"

      when "group"
        return if ids.length >= 3

        raise ArgumentError,
              "Group conversations require " \
              "at least three participants"
      end
    end

    def start_direct(ids, profiles)
      direct_key =
        ids.join(":")

      existing =
        Conversation.find_by(
          kind: "direct",
          direct_key: direct_key
        )

      return existing if existing

      create_conversation(
        ids: ids,
        profiles: profiles,
        direct_key: direct_key,
        title: nil
      )
    rescue ActiveRecord::RecordNotUnique
      Conversation.find_by!(
        kind: "direct",
        direct_key: direct_key
      )
    end

    def start_group(ids, profiles)
      raise ArgumentError,
            "Group title is required" \
        if title.blank?

      create_conversation(
        ids: ids,
        profiles: profiles,
        direct_key: nil,
        title: title
      )
    end

    def create_conversation(
      ids:,
      profiles:,
      direct_key:,
      title:
    )
      Conversation.transaction do
        conversation =
          Conversation.create!(
            kind: kind,
            title: title,
            direct_key: direct_key,
            created_by_profile:
              creator_profile
          )

        ids.each do |profile_id|
          Participant.create!(
            conversation:
              conversation,
            profile:
              profiles.fetch(
                profile_id
              ),
            role:
              profile_id ==
              creator_profile.id ?
                "owner" :
                "member",
            joined_at:
              Time.current
          )
        end

        conversation
      end
    end
  end
end
