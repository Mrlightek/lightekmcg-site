# db/migrate/YYYYMMDDHHMMSS_create_susu_tables.rb
class CreateSusuTables < ActiveRecord::Migration[8.0]
  def change
    create_table :susu_groups do |t|
      t.string :name, null: false
      t.decimal :contribution_amount, precision: 10, scale: 2, null: false
      t.string :cycle_frequency, null: false, default: "monthly" # e.g., weekly, monthly
      t.integer :current_cycle, null: false, default: 1
      t.integer :status, null: false, default: 0 # enum: draft: 0, active: 1, completed: 2
      t.references :organizer, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    create_table :susu_memberships do |t|
      t.references :susu_group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :payout_position, null: false # Position in rotation (1, 2, 3...)
      t.boolean :payout_received, null: false, default: false

      t.timestamps
    end

    # Ensure a user isn't added twice and payout positions are unique per group
    add_index :susu_memberships, [:susu_group_id, :user_id], unique: true
    add_index :susu_memberships, [:susu_group_id, :payout_position], unique: true

    create_table :susu_contributions do |t|
      t.references :susu_group, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :cycle_number, null: false

      t.timestamps
    end

    # Prevent a user from contributing more than once per cycle
    add_index :susu_contributions, [:susu_group_id, :user_id, :cycle_number], 
              unique: true, 
              name: "idx_susu_contributions_unique_per_cycle"
  end
end