class AddJurisdictionMonitoring < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_people_employments, :compliance_access, :string, null: false, default: 'none'
    create_table :lightek_compliance_monitors do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.string :state, null: false
      t.string :provider, null: false
      t.string :query, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :next_run_at, null: false
      t.datetime :last_checked_at
      t.string :error_code
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
  end
end
