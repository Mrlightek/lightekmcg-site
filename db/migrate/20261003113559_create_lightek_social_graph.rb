# frozen_string_literal: true

class CreateLightekSocialGraph <
      ActiveRecord::Migration[8.0]

  def change
    create_table :lightek_social_follows do |t|
      t.references :follower_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.references :followed_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.timestamps
    end

    add_index :lightek_social_follows,
              [
                :follower_profile_id,
                :followed_profile_id
              ],
              unique: true,
              name:
                "idx_lightek_social_follows_pair"

    add_index :lightek_social_follows,
              :followed_profile_id

    add_check_constraint(
      :lightek_social_follows,
      "follower_profile_id <> followed_profile_id",
      name:
        "chk_lightek_social_follow_not_self"
    )

    create_table :lightek_social_friendships do |t|
      t.references :requester_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.references :addressee_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.string :pair_key,
               null: false

      t.string :status,
               null: false,
               default: "pending"

      t.datetime :responded_at
      t.datetime :accepted_at
      t.datetime :ended_at

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_social_friendships,
              :pair_key,
              unique: true

    add_index :lightek_social_friendships,
              :requester_profile_id

    add_index :lightek_social_friendships,
              :addressee_profile_id

    add_index :lightek_social_friendships,
              :status

    add_check_constraint(
      :lightek_social_friendships,
      "requester_profile_id <> addressee_profile_id",
      name:
        "chk_lightek_social_friendship_not_self"
    )

    create_table :lightek_social_blocks do |t|
      t.references :blocker_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.references :blocked_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.string :reason_code

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_social_blocks,
              [
                :blocker_profile_id,
                :blocked_profile_id
              ],
              unique: true,
              name:
                "idx_lightek_social_blocks_pair"

    add_index :lightek_social_blocks,
              :blocked_profile_id

    add_check_constraint(
      :lightek_social_blocks,
      "blocker_profile_id <> blocked_profile_id",
      name:
        "chk_lightek_social_block_not_self"
    )

    create_table :lightek_social_circles do |t|
      t.references :owner_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   }

      t.string :name,
               null: false

      t.string :name_key,
               null: false

      t.integer :position,
                null: false,
                default: 0

      t.jsonb :settings,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_social_circles,
              [
                :owner_profile_id,
                :name_key
              ],
              unique: true,
              name:
                "idx_lightek_social_circles_owner_name"

    create_table :lightek_social_circle_memberships do |t|
      t.references :circle,
                   null: false,
                   foreign_key: {
                     to_table:
                       :lightek_social_circles
                   }

      t.references :profile,
                   null: false,
                   foreign_key: true

      t.integer :position,
                null: false,
                default: 0

      t.text :note

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_social_circle_memberships,
              [
                :circle_id,
                :profile_id
              ],
              unique: true,
              name:
                "idx_lightek_social_circle_members_pair"

    create_table :lightek_social_relationship_events do |t|
      t.references :actor_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.references :target_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.string :pair_key,
               null: false

      t.string :event_type,
               null: false

      t.boolean :counts_toward_strength,
                null: false,
                default: true

      t.string :context_type
      t.bigint :context_id

      t.string :source_key

      t.datetime :occurred_at,
                 null: false

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_social_relationship_events,
              [
                :pair_key,
                :occurred_at
              ],
              name:
                "idx_lightek_social_relationship_events_pair_time"

    add_index :lightek_social_relationship_events,
              [
                :actor_profile_id,
                :occurred_at
              ],
              name:
                "idx_lightek_social_relationship_events_actor"

    add_index :lightek_social_relationship_events,
              [
                :target_profile_id,
                :occurred_at
              ],
              name:
                "idx_lightek_social_relationship_events_target"

    add_index :lightek_social_relationship_events,
              [
                :context_type,
                :context_id
              ],
              name:
                "idx_lightek_social_relationship_events_context"

    add_index :lightek_social_relationship_events,
              :source_key,
              unique: true,
              where:
                "source_key IS NOT NULL"

    add_check_constraint(
      :lightek_social_relationship_events,
      "actor_profile_id <> target_profile_id",
      name:
        "chk_lightek_social_relationship_event_not_self"
    )

    create_table :lightek_social_relationship_strengths do |t|
      t.references :profile_a,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.references :profile_b,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.string :pair_key,
               null: false

      t.decimal :reciprocity,
                precision: 5,
                scale: 4,
                null: false,
                default: 0

      t.decimal :continuity,
                precision: 5,
                scale: 4,
                null: false,
                default: 0

      t.decimal :context_diversity,
                precision: 5,
                scale: 4,
                null: false,
                default: 0

      t.decimal :shared_experience,
                precision: 5,
                scale: 4,
                null: false,
                default: 0

      t.decimal :recency,
                precision: 5,
                scale: 4,
                null: false,
                default: 0

      t.decimal :confidence,
                precision: 5,
                scale: 4,
                null: false,
                default: 0

      t.integer :observed_event_count,
                null: false,
                default: 0

      t.datetime :first_observed_at
      t.datetime :last_observed_at
      t.datetime :computed_at

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_social_relationship_strengths,
              :pair_key,
              unique: true

    add_index :lightek_social_relationship_strengths,
              :profile_a_id

    add_index :lightek_social_relationship_strengths,
              :profile_b_id

    add_check_constraint(
      :lightek_social_relationship_strengths,
      "profile_a_id <> profile_b_id",
      name:
        "chk_lightek_social_strength_not_self"
    )

    %w[
      reciprocity
      continuity
      context_diversity
      shared_experience
      recency
      confidence
    ].each do |column|
      add_check_constraint(
        :lightek_social_relationship_strengths,
        "#{column} >= 0 AND #{column} <= 1",
        name:
          "chk_lightek_social_strength_#{column}"
      )
    end

    create_table :lightek_social_connection_opportunities do |t|
      t.references :profile,
                   null: false,
                   foreign_key: true,
                   index: false

      t.references :related_profile,
                   null: false,
                   foreign_key: {
                     to_table: :profiles
                   },
                   index: false

      t.string :kind,
               null: false

      t.string :status,
               null: false,
               default: "pending"

      t.string :reason_code

      t.string :context_type
      t.bigint :context_id

      t.string :source_key

      t.datetime :detected_at,
                 null: false

      t.datetime :expires_at
      t.datetime :acted_at
      t.datetime :dismissed_at

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :lightek_social_connection_opportunities,
              [
                :profile_id,
                :status,
                :detected_at
              ],
              name:
                "idx_lightek_social_opportunities_profile_state"

    add_index :lightek_social_connection_opportunities,
              [
                :related_profile_id,
                :status
              ],
              name:
                "idx_lightek_social_opportunities_related"

    add_index :lightek_social_connection_opportunities,
              [
                :context_type,
                :context_id
              ],
              name:
                "idx_lightek_social_opportunities_context"

    add_index :lightek_social_connection_opportunities,
              :source_key,
              unique: true,
              where:
                "source_key IS NOT NULL"

    add_check_constraint(
      :lightek_social_connection_opportunities,
      "profile_id <> related_profile_id",
      name:
        "chk_lightek_social_opportunity_not_self"
    )
  end
end
