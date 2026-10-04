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

        when "group_add_members"
          group_add_members

        when "group_remove_member"
          group_remove_member

        when "group_promote_admin"
          group_promote_admin

        when "group_demote_admin"
          group_demote_admin

        when "delete"
          delete_conversation

        when "leave"
          leave_group

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

      def group_remove_member
        record =
          conversation

        target =
          Profile.find(
            payload.fetch(
              "profile_id"
            )
          )

        member =
          RemoveGroupParticipant.call(
            conversation:
              record,

            actor_profile:
              profile,

            target_profile:
              target
          )

        {
          "removed_profile_id" =>
            member.profile_id,

          "left_at" =>
            member
              .left_at
              .iso8601,

          "conversation" =>
            conversation_payload(
              record.reload,
              detailed: true
            )
        }
      end

      def group_promote_admin
        record =
          conversation

        target =
          Profile.find(
            payload.fetch(
              "profile_id"
            )
          )

        member =
          ChangeGroupParticipantRole.call(
            conversation:
              record,

            actor_profile:
              profile,

            target_profile:
              target,

            role:
              "admin"
          )

        {
          "participant" =>
            participant_payload(
              member
            ),

          "conversation" =>
            conversation_payload(
              record.reload,
              detailed: true
            )
        }
      end

      def group_demote_admin
        record =
          conversation

        target =
          Profile.find(
            payload.fetch(
              "profile_id"
            )
          )

        member =
          ChangeGroupParticipantRole.call(
            conversation:
              record,

            actor_profile:
              profile,

            target_profile:
              target,

            role:
              "member"
          )

        {
          "participant" =>
            participant_payload(
              member
            ),

          "conversation" =>
            conversation_payload(
              record.reload,
              detailed: true
            )
        }
      end

      def group_add_members
        record =
          conversation

        ids =
          Array(
            payload.fetch(
              "profile_ids"
            )
          )
            .map(&:to_i)
            .uniq

        profiles =
          Profile
            .where(
              id:
                ids
            )
            .index_by(
              &:id
            )

        unless profiles.length == ids.length
          raise ActiveRecord::RecordNotFound,
                "One or more profiles could not be found"
        end

        members =
          AddGroupParticipants.call(
            conversation:
              record,

            actor_profile:
              profile,

            target_profiles:
              ids.map do |profile_id|
                profiles.fetch(
                  profile_id
                )
              end
          )

        {
          "participants" =>
            members.map do |member|
              participant_payload(
                member
              )
            end,

          "conversation" =>
            conversation_payload(
              record.reload,
              detailed: true
            )
        }
      end

      def delete_conversation
        record =
          conversation

        member =
          DeleteConversationForProfile.call(
            conversation:
              record,

            profile:
              profile
          )

        {
          "conversation_id" =>
            record.id,

          "profile_id" =>
            profile.id,

          "deleted_for_me" =>
            true,

          "left_at" =>
            member
              .left_at
              .iso8601
        }
      end

      def leave_group
        record =
          conversation

        member =
          LeaveGroup.call(
            conversation:
              record,

            profile:
              profile
          )

        {
          "conversation_id" =>
            record.id,

          "profile_id" =>
            profile.id,

          "left_group" =>
            true,

          "left_at" =>
            member
              .left_at
              .iso8601
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

        participant_records =
          record
            .participants
            .includes(
              :profile
            )
            .order(
              :id
            )

        participant_records =
          participant_records.active unless
            record.direct?

        participants =
          participant_records.map do |entry|
            participant_payload(
              entry
            )
          end

        direct_peer_member =
          if record.direct?
            record
              .participants
              .includes(
                :profile
              )
              .where
              .not(
                profile_id:
                  profile.id
              )
              .first
          end

        messaging_blocked =
          direct_peer_member &&
          LightekSocial.blocked_between?(
            profile,
            direct_peer_member.profile
          )

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
            .where(
              "created_at >= ?",
              member.joined_at
            )
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
            last_message
              &.created_at
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
