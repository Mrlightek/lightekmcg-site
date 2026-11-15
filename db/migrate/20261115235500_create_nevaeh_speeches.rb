class CreateNevaehSpeeches < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_speeches do |t|
      t.references :user,null:false,foreign_key:true
      t.string :request_key,null:false
      t.string :fingerprint,null:false
      t.text :text,null:false
      t.string :voice,null:false,default:'en-us+f3'
      t.integer :speed,null:false,default:170
      t.string :status,null:false,default:'queued'
      t.float :duration
      t.json :mouth_frames,null:false,default:[]
      t.boolean :truncated,null:false,default:false
      t.text :error
      t.datetime :started_at
      t.datetime :expires_at,null:false
      t.timestamps
    end
    add_index :nevaeh_speeches,[:user_id,:request_key],unique:true
    add_index :nevaeh_speeches,[:status,:started_at]
    add_index :nevaeh_speeches,:expires_at
  end
end
