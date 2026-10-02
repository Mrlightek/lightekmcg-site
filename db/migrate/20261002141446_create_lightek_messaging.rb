# frozen_string_literal: true

class CreateLightekMessaging < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_messaging_conversations do |t|
      t.string :kind,
               null: false,
               default: "direct"

      t.string :title
      t.string :direct_key

      t.references :created_by_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   }

      t.datetime :last_message_at

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_messaging_conversations,
              :direct_key,
              unique: true,
              where: "direct_key IS NOT NULL"

    add_index :lightek_messaging_conversations,
              [:kind, :updated_at]

    add_check_constraint(
      :lightek_messaging_conversations,
      "kind IN ('direct', 'group', 'community', 'watch_party')",
      name: "lightek_messaging_conversations_kind_check"
    )

    add_check_constraint(
      :lightek_messaging_conversations,
      "(kind = 'direct' AND direct_key IS NOT NULL) OR "       "(kind <> 'direct' AND direct_key IS NULL)",
      name: "lightek_messaging_conversations_direct_key_check"
    )

    add_check_constraint(
      :lightek_messaging_conversations,
      "kind <> 'group' OR "       "(title IS NOT NULL AND btrim(title) <> '')",
      name: "lightek_messaging_conversations_group_title_check"
    )

    create_table :lightek_messaging_participants do |t|
      t.references :conversation,
                   null: false,
                   foreign_key: {
                     to_table:
                       :lightek_messaging_conversations
                   }

      t.references :profile,
                   null: false,
                   foreign_key: true

      t.string :role,
               null: false,
               default: "member"

      t.datetime :joined_at,
                 null: false,
                 default: -> { "CURRENT_TIMESTAMP" }

      t.datetime :last_read_at
      t.datetime :left_at

      t.jsonb :settings,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_messaging_participants,
              [:conversation_id, :profile_id],
              unique: true,
              name:
                "idx_lightek_messaging_participants_unique"

    add_index :lightek_messaging_participants,
              [:profile_id, :left_at],
              name:
                "idx_lightek_messaging_participants_active"

    add_check_constraint(
      :lightek_messaging_participants,
      "role IN ('owner', 'admin', 'member')",
      name: "lightek_messaging_participants_role_check"
    )

    add_check_constraint(
      :lightek_messaging_participants,
      "left_at IS NULL OR left_at >= joined_at",
      name: "lightek_messaging_participants_left_at_check"
    )

    create_table :lightek_messaging_messages do |t|
      t.references :conversation,
                   null: false,
                   foreign_key: {
                     to_table:
                       :lightek_messaging_conversations
                   }

      t.references :sender_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   }

      t.bigint :reply_to_message_id

      t.string :message_type,
               null: false,
               default: "text"

      t.text :body,
             null: false

      t.jsonb :metadata,
              null: false,
              default: {}

      t.datetime :edited_at

      t.timestamps
    end

    add_foreign_key(
      :lightek_messaging_messages,
      :lightek_messaging_messages,
      column: :reply_to_message_id
    )

    add_index :lightek_messaging_messages,
              [:conversation_id, :created_at],
              name:
                "idx_lightek_messaging_messages_timeline"

    add_index :lightek_messaging_messages,
              :reply_to_message_id

    add_check_constraint(
      :lightek_messaging_messages,
      "message_type IN ('text', 'system')",
      name: "lightek_messaging_messages_type_check"
    )

    add_check_constraint(
      :lightek_messaging_messages,
      "char_length(btrim(body)) > 0",
      name: "lightek_messaging_messages_body_check"
    )
  end
end
