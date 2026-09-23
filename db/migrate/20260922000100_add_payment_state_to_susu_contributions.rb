class AddPaymentStateToSusuContributions < ActiveRecord::Migration[8.0]
  def up
    add_column :susu_contributions, :status, :string, null: false, default: "pending"
    add_column :susu_contributions, :paid_at, :datetime
    add_column :susu_contributions, :failure_message, :text
    add_index :susu_contributions, :status

    # Contributions created before the payment lifecycle existed represented
    # already-recorded contributions, so preserve them as settled history.
    execute <<~SQL
      UPDATE susu_contributions
      SET status = 'succeeded', paid_at = COALESCE(updated_at, created_at)
    SQL
  end

  def down
    remove_index :susu_contributions, :status
    remove_column :susu_contributions, :failure_message
    remove_column :susu_contributions, :paid_at
    remove_column :susu_contributions, :status
  end
end
