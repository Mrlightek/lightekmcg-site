class AddSharedHostingAccounts < ActiveRecord::Migration[8.0]
  def up
    add_column :lightek_pwa_member_backends, :hosting_mode, :string, null: false, default: 'shared_account'
    add_column :lightek_pwa_member_backends, :account_receipt, :jsonb, null: false, default: {}
    add_reference :lightek_pwa_shared_pools, :standby_launch, foreign_key: {to_table: :gatekeeper_application_launches}
    # Existing installations contain real data. Keep their original transfer
    # protocol unless their single-customer runtime can be reused in place.
    execute "UPDATE lightek_pwa_member_backends SET hosting_mode = 'legacy_runtime'"
    adopt_single_customer_runtimes!
  end

  def adopt_single_customer_runtimes!
    # When a pool has exactly one verified customer runtime, make that runtime
    # the shared host. The customer's existing rows, originals, post IDs and
    # hostname stay in place. Keep the unused empty pool runtime as a standby;
    # the SSH installer pauses it only after shared-account health passes.
    candidates = connection.select_all(<<~SQL)
      SELECT b.id AS backend_id, b.shared_pool_id, b.launch_id, p.launch_id AS standby_id,
        p.max_members, standby.template_snapshot AS standby_template
      FROM lightek_pwa_member_backends b
      JOIN lightek_pwa_shared_pools p ON p.id = b.shared_pool_id
      JOIN gatekeeper_application_launches l ON l.id = b.launch_id
      LEFT JOIN gatekeeper_application_launches standby ON standby.id = p.launch_id
      WHERE b.status = 'shared_ready' AND b.hosting_mode = 'legacy_runtime' AND l.status = 'ready' AND l.domain = b.hostname
        AND l.gatekeeper_node_id = p.node_id AND l.owner_id = b.user_id
        AND NOT EXISTS (SELECT 1 FROM lightek_pwa_member_backends other
          WHERE other.shared_pool_id = p.id AND other.id <> b.id AND other.status <> 'retired')
    SQL
    candidates.each do |row|
      template = row['standby_template'].is_a?(Hash) ? row['standby_template'] : JSON.parse(row['standby_template'].presence || '{}')
      limit = row['max_members'].to_i == 1 && template.dig('pwa_pool', 'profile') == 'starter' ? 25 : Integer(row['max_members'])
      execute "UPDATE lightek_pwa_shared_pools SET launch_id = #{Integer(row['launch_id'])}, standby_launch_id = #{row['standby_id'] ? Integer(row['standby_id']) : 'NULL'}, max_members = #{limit} WHERE id = #{Integer(row['shared_pool_id'])}"
      execute "UPDATE lightek_pwa_member_backends SET hosting_mode = 'shared_account' WHERE id = #{Integer(row['backend_id'])}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Shared accounts cannot be converted to individual runtimes by removing columns'
  end
end
