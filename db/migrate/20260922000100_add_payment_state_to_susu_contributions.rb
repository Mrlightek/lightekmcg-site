class AddPaymentStateToSusuContributions < ActiveRecord::Migration[8.0]
  def up
    # This migration sorts before CreateSusuTables on a fresh install.
    # If the table does not exist yet, CreateSusuTables defines these fields.
    return unless table_exists?(:susu_contributions)

    add_column :susu_contributions, :status, :string, null: false, default: "pending" unless column_exists?(:susu_contributions, :status)
    add_column :susu_contributions, :paid_at, :datetime unless column_exists?(:susu_contributions, :paid_at)
    add_column :susu_contributions, :failure_message, :text unless column_exists?(:susu_contributions, :failure_message)
    add_index :susu_contributions, :status unless index_exists?(:susu_contributions, :status)

    execute <<~SQL
      UPDATE susu_contributions
      SET status = 'succeeded', paid_at = COALESCE(updated_at, created_at)
      WHERE status = 'pending'
    SQL
  end

  def down
    return unless table_exists?(:susu_contributions)

    remove_index :susu_contributions, :status if index_exists?(:susu_contributions, :status)
    remove_column :susu_contributions, :failure_message if column_exists?(:susu_contributions, :failure_message)
    remove_column :susu_contributions, :paid_at if column_exists?(:susu_contributions, :paid_at)
    remove_column :susu_contributions, :status if column_exists?(:susu_contributions, :status)
  end
end
