class CreateLightekManagedDnsEnrollments < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_managed_dns_enrollments do |t|
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.references :owner, null: false, foreign_key: {to_table: :users}
      t.references :requested_by, null: false, foreign_key: {to_table: :users}
      t.references :reviewed_by, foreign_key: {to_table: :users}
      t.string :domain, null: false
      t.string :state, null: false, default: "requested"
      t.string :proof, null: false
      t.string :provider_zone_id
      t.string :records_digest
      t.jsonb :previous_nameservers, null: false, default: []
      t.jsonb :nameservers, null: false, default: []
      t.datetime :reviewed_at
      t.datetime :verified_at
      t.timestamps
    end
    add_index :lightek_managed_dns_enrollments, :domain, unique: true, where: "state <> 'withdrawn'"
    add_index :lightek_managed_dns_enrollments, :provider_zone_id, unique: true, where: "state <> 'withdrawn'"
  end
end
