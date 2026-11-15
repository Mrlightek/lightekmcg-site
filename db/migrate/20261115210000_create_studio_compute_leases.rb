class CreateStudioComputeLeases < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_compute_pools do |t|
      t.string :name, null: false
    end
    add_index :studio_compute_pools, :name, unique: true
    create_table :studio_compute_leases do |t|
      t.references :studio_operation, null: false, foreign_key: true, index: {unique: true}
      t.string :tenant_key, null: false
      t.string :token, null: false
      t.string :worker, null: false
      t.datetime :expires_at, null: false
      t.datetime :released_at
      t.timestamps
    end
    add_index :studio_compute_leases, [:tenant_key, :expires_at]
  end
end
