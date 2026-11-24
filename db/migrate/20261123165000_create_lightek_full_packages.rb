class CreateLightekFullPackages < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_full_packages do |t|
      t.references :order, null: false, foreign_key: { to_table: :lightek_commerce_orders }, index: { unique: true }
      t.references :buyer, null: false, foreign_key: { to_table: :users }
      t.string :peer_ip, null: false
      t.string :tunnel_secret_slug, null: false
      t.string :voice_secret_slug, null: false
      t.string :group_id, null: false
      t.string :request_key, null: false
      t.datetime :tunnel_ready_at
      t.timestamps
    end
    add_index :lightek_full_packages, :peer_ip, unique: true
  end
end
