class CreateStudioWorkstations < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_workstations do |t|
      t.references :owner, null:false, foreign_key:{to_table: :users}
      t.references :site
      t.references :studio_scene, null:false, foreign_key:true
      t.string :session_key, null:false
      t.string :request_key, null:false
      t.string :status, null:false, default:"starting"
      t.string :container_id
      t.integer :port
      t.datetime :expires_at, null:false
      t.jsonb :metadata, null:false, default:{}
      t.text :error_message
      t.timestamps
    end
    add_index :studio_workstations,:session_key,unique:true
    add_index :studio_workstations,[:owner_id,:request_key],unique:true
  end
end
