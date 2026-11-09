class CreateLightekAudienceLeases < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_audience_leases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :key, null: false
      t.string :source, null: false
      t.datetime :expires_at, null: false
    end
    add_index :lightek_audience_leases, :key, unique: true
    add_index :lightek_audience_leases, :expires_at
  end
end
