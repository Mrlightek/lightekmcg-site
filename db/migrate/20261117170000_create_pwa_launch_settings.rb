class CreatePwaLaunchSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_launch_settings do |t|
      t.json :settings, default: {}, null: false
      t.references :updated_by, foreign_key: {to_table: :users}
      t.timestamps
    end
  end
end
