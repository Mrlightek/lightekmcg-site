class ExpandProfilesForLightekIdentity < ActiveRecord::Migration[8.0]
  def up
    add_column :profiles, :display_name, :string
    add_column :profiles, :handle, :string
    add_column :profiles, :profile_type,
               :string,
               null: false,
               default: "person"
    add_column :profiles, :avatar_url, :string
    add_column :profiles, :cover_image_url, :string

    duplicate_user_ids =
      select_values(<<~SQL)
        SELECT user_id
        FROM profiles
        GROUP BY user_id
        HAVING COUNT(*) > 1
      SQL

    if duplicate_user_ids.any?
      raise <<~MESSAGE
        Cannot enforce one profile per user.
        Duplicate profile user_ids:
        #{duplicate_user_ids.join(", ")}
      MESSAGE
    end

    # Existing profiles get privacy-neutral handles.
    execute <<~SQL
      UPDATE profiles
      SET handle = 'member-' || user_id
      WHERE handle IS NULL OR BTRIM(handle) = ''
    SQL

    # Every existing Rails account gets exactly one profile.
    # No real name or email address is copied into the public identity.
    execute <<~SQL
      INSERT INTO profiles (
        user_id,
        handle,
        profile_type,
        created_at,
        updated_at
      )
      SELECT
        users.id,
        'member-' || users.id,
        'person',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      LEFT JOIN profiles
        ON profiles.user_id = users.id
      WHERE profiles.id IS NULL
    SQL

    change_column_null :profiles, :handle, false

    remove_index :profiles, :user_id if index_exists?(:profiles, :user_id)

    add_index :profiles,
              :user_id,
              unique: true

    add_index :profiles,
              :handle,
              unique: true

    create_table :profile_sections do |t|
      t.references :profile,
                   null: false,
                   foreign_key: true

      t.string :key,
               null: false

      t.integer :position,
                null: false,
                default: 0

      t.boolean :enabled,
                null: false,
                default: true

      t.jsonb :settings,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :profile_sections,
              [:profile_id, :key],
              unique: true

    add_index :profile_sections,
              [:profile_id, :position]

    # Backfilled profiles are "person" profiles by default.
    # Seed the My Space section structure without exposing private account data.
    execute <<~SQL
      INSERT INTO profile_sections (
        profile_id,
        key,
        position,
        enabled,
        settings,
        created_at,
        updated_at
      )
      SELECT
        profiles.id,
        defaults.key,
        defaults.position,
        TRUE,
        '{}'::jsonb,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM profiles
      CROSS JOIN (
        VALUES
          ('posts', 1),
          ('friends', 2),
          ('communities', 3),
          ('events', 4),
          ('about', 5)
      ) AS defaults(key, position)
    SQL
  end

  def down
    drop_table :profile_sections

    remove_index :profiles, :handle if index_exists?(:profiles, :handle)
    remove_index :profiles, :user_id if index_exists?(:profiles, :user_id)

    add_index :profiles, :user_id

    remove_column :profiles, :cover_image_url
    remove_column :profiles, :avatar_url
    remove_column :profiles, :profile_type
    remove_column :profiles, :handle
    remove_column :profiles, :display_name
  end
end
