class CreateSusuCyclesRoundsCommitmentsAndMatching < ActiveRecord::Migration[8.0]
  def change
    add_column :susu_groups, :current_round_number, :integer, null: false, default: 1

    add_column :susu_memberships, :commitment_status, :string, null: false, default: "pending"
    add_column :susu_memberships, :autopay_enabled, :boolean, null: false, default: false
    add_column :susu_memberships, :joined_at, :datetime
    add_column :susu_memberships, :exit_requested_at, :datetime

    create_table :susu_cycles do |t|
      t.references :susu_group, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :starts_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :susu_cycles, [:susu_group_id, :number], unique: true

    create_table :susu_rounds do |t|
      t.references :susu_cycle, null: false, foreign_key: true
      t.integer :number, null: false
      t.references :recipient_membership, null: false, foreign_key: { to_table: :susu_memberships }
      t.datetime :due_at
      t.string :status, null: false, default: "scheduled"
      t.decimal :expected_pot, precision: 12, scale: 2, null: false, default: 0
      t.decimal :collected_amount, precision: 12, scale: 2, null: false, default: 0
      t.datetime :paid_out_at
      t.timestamps
    end
    add_index :susu_rounds, [:susu_cycle_id, :number], unique: true

    create_table :susu_commitments do |t|
      t.references :susu_membership, null: false, foreign_key: true
      t.references :susu_cycle, foreign_key: true
      t.decimal :contribution_amount, precision: 12, scale: 2, null: false
      t.integer :rounds_committed, null: false
      t.decimal :remaining_amount, precision: 12, scale: 2, null: false
      t.datetime :accepted_at
      t.string :terms_version, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    create_table :susu_match_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :contribution_amount, precision: 12, scale: 2, null: false
      t.string :cycle_frequency, null: false
      t.decimal :desired_payout, precision: 12, scale: 2, null: false
      t.integer :desired_member_count, null: false
      t.string :matching_mode, null: false, default: "suggestions"
      t.string :status, null: false, default: "open"
      t.timestamps
    end

    add_column :susu_contributions, :round_number, :integer, null: false, default: 1
    add_reference :susu_contributions, :susu_round, foreign_key: true
    add_reference :susu_contributions, :susu_membership, foreign_key: true
    add_column :susu_contributions, :next_retry_at, :datetime
    add_column :susu_contributions, :attempt_count, :integer, null: false, default: 0

    if index_name_exists?(:susu_contributions, "idx_susu_contributions_unique_per_cycle")
      remove_index :susu_contributions, name: "idx_susu_contributions_unique_per_cycle"
    end

    add_index :susu_contributions,
              [:susu_group_id, :user_id, :cycle_number, :round_number],
              unique: true,
              name: "idx_susu_contributions_unique_per_round"
  end
end
