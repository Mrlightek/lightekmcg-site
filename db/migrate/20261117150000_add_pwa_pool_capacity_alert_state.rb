class AddPwaPoolCapacityAlertState < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_pwa_shared_pools, :capacity_alert_state, :string, null: false, default: 'normal'
  end
end
