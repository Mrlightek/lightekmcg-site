# frozen_string_literal: true

module LightekMessaging
  module Workers
    class Pwa
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
        when "people"
          people

        when "list"
          list

        when "show"
          show

        when "start"
          start

        when "send"
          send_message

        when "mark_read"
          mark_read

        else
          raise ArgumentError,
                "Unsupported Messaging action: #{action}"
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
            AccessDenied,
            "A Lightek profile is required for Messages"
          )
      end

      def accessible_conversations
        Conversation
          .joins(:participants)
          .merge(
            Participant
              .active
              .where(
                profile_id:
                  profile.id
              )
          )
      end

      def conversation
        @conversation ||=
          accessible_conversations.find(
            payload.fetch(
              "conversation_id"
            )
          )

      rescue ActiveRecord::RecordNotFound
        raise AccessDenied,
              "Conversation is unavailable"
      end

      def participation(record = conversation)
        record
          .participants
          .active
          .find_by(
            profile_id:
              profile.id
          ) ||
          raise(
            AccessDenied,
            "You are not an active participant in this conversation"
          )
      end

      def people
        query =
          payload[
            "query"
          ]
            .to_s
            .strip

        records =
          Profile
            .where
            .not(
              id:
                profile.id
            )

        if query.present?
          pattern =
            "%" +
            ActiveRecord::Base
              .sanitize_sql_like(
                query
              ) +
            "%"

          records =
            records.where(
              "display_name ILIKE :pattern " \
              "OR handle ILIKE :pattern",
              pattern:
                pattern
            )
        end

        records =
          records
            .order(
              :display_name,
              :handle,
              :id
            )
            .limit(30)

        {
          "profiles" =>
            records.map do |record|
              profile_payload(
                record
              )
            end
        }
      end

      def list
        records =
          accessible_conversations
            .recent_first
            .limit(50)

        {
          "conversations" =>
            records.map do |record|
              conversation_payload(
                record
              )
            end
        }
      end

      def show
        {
          "conversation" =>
            conversation_payload(
              conversation,
              detailed: true
            )
        }
      end

      def start
        record =
          StartConversation.call(
            creator_profile:
              profile,

            participant_profile_ids:
              Array(
                payload.fetch(
                  "participant_profile_ids"
                )
              ),

            kind:
              payload.fetch(
                "kind"
              ),

            title:
              payload["title"]
          )

        {
          "conversation" =>
            conversation_payload(
              record,
              detailed: true
            )
        }
      end

      def send_message
        record =
          conversation

        reply =
          if payload[
               "reply_to_message_id"
             ].present?

            record
              .messages
              .find(
                payload[
                  "reply_to_message_id"
                ]
              )
          end

        message =
          SendMessage.call(
            conversation:
              record,

            sender_profile:
              profile,

            body:
              payload.fetch(
                "body"
              ),

            reply_to_message:
              reply,

            message_type:
              "text",

            metadata:
              {}
          )

        {
          "message" =>
            message_payload(
              message
            ),

          "conversation" =>
            conversation_payload(
              record.reload
            )
        }
      end

      def mark_read
        member =
          participation

        read_at =
          Time.current

        member.mark_read!(
          at: read_at
        )

        {
          "conversation_id" =>
            conversation.id,

          "profile_id" =>
            profile.id,

          "last_read_at" =>
            read_at.iso8601,

          "unread_count" =>
            unread_count(
              conversation,
              member
            )
        }
      end

      def conversation_payload(
        record,
        detailed: false
      )
        member =
          participation(record)

        participants =
          record
            .participants
            .active
            .includes(:profile)
            .order(:id)
            .map do |entry|

              participant_payload(
                entry
              )
            end

        messaging_blocked =
          if record.direct?
            peer_profile =
              record
                .participants
                .active
                .includes(
                  :profile
                )
                .map(
                  &:profile
                )
                .find do |candidate|
                  candidate.id !=
                    profile.id
                end

            peer_profile &&
              LightekSocial.blocked_between?(
                profile,
                peer_profile
              )
          else
            false
          end

        peer =
          if record.direct?
            participants.find do |entry|
              entry["profile"]["id"] !=
                profile.id
            end
          end

        last_message =
          record
            .messages
            .includes(
              :sender_profile
            )
            .order(
              created_at: :desc,
              id: :desc
            )
            .first

        result = {
          "id" =>
            record.id,

          "kind" =>
            record.kind,

          "title" =>
            if record.direct?
              peer
                &.dig(
                  "profile",
                  "name"
                ) ||
                "Direct message"
            else
              record.title
            end,

          "avatar_url" =>
            if record.direct?
              peer
                &.dig(
                  "profile",
                  "avatar_url"
                )
            end,

          "created_by_profile_id" =>
            record.created_by_profile_id,

          "participant_count" =>
            participants.length,

          "participants" =>
            participants,

          "current_role" =>
            member.role,

          "messaging_blocked" =>
            !!messaging_blocked,

          "unread_count" =>
            unread_count(
              record,
              member
            ),

          "last_message" =>
            if last_message
              message_payload(
                last_message,
                compact: true
              )
            end,

          "last_message_at" =>
            record
              .last_message_at
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

        if detailed
          visible_messages =
            record
              .messages
              .where(
                "created_at >= ?",
                member.joined_at
              )
              .includes(
                :sender_profile
              )
              .order(
                :created_at,
                :id
              )
              .last(100)

          result["messages"] =
            visible_messages.map do |message|
              message_payload(
                message
              )
            end
        end

        result
      end

      def participant_payload(entry)
        {
          "role" =>
            entry.role,

          "joined_at" =>
            entry
              .joined_at
              .iso8601,

          "profile" =>
            profile_payload(
              entry.profile
            )
        }
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

      def message_payload(
        record,
        compact: false
      )
        result = {
          "id" =>
            record.id,

          "conversation_id" =>
            record.conversation_id,

          "body" =>
            record.body,

          "message_type" =>
            record.message_type,

          "reply_to_message_id" =>
            record.reply_to_message_id,

          "sender" =>
            profile_payload(
              record.sender_profile
            ),

          "edited_at" =>
            record
              .edited_at
              &.iso8601,

          "created_at" =>
            record
              .created_at
              .iso8601
        }

        if compact
          result.slice(
            "id",
            "body",
            "sender",
            "created_at"
          )
        else
          result
        end
      end

      def unread_count(
        record,
        member
      )
        baseline =
          [
            member.joined_at,
            member.last_read_at
          ]
            .compact
            .max

        scope =
          record
            .messages
            .where
            .not(
              sender_profile_id:
                profile.id
            )

        if baseline
          scope =
            scope.where(
              "created_at > ?",
              baseline
            )
        end

        scope.count
      end
    end
  end
end
