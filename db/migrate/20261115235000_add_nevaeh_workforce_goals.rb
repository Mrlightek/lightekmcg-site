class AddNevaehWorkforceGoals < ActiveRecord::Migration[8.0]
  def change
    add_column :nevaeh_os_agents,:deleted_at,:datetime
    add_column :nevaeh_agent_workers,:deleted_at,:datetime
    create_table :nevaeh_goals do |t|
      t.references :user,null:false,foreign_key:true
      t.string :title,null:false
      t.string :request_key,null:false
      t.string :fingerprint,null:false
      t.string :status,null:false,default:'draft'
      t.text :error
      t.integer :lock_version,null:false,default:0
      t.timestamps
    end
    add_index :nevaeh_goals,[:user_id,:request_key],unique:true
    create_table :nevaeh_goal_steps do |t|
      t.references :nevaeh_goal,null:false,foreign_key:true
      t.references :nevaeh_os_agent,null:false,foreign_key:true
      t.references :nevaeh_agent_run,foreign_key:true
      t.string :key,null:false
      t.string :label,null:false
      t.integer :position,null:false
      t.string :status,null:false,default:'waiting'
      t.json :command,null:false,default:{}
      t.json :expectations,null:false,default:[]
      t.json :evidence,null:false,default:{}
      t.text :error
      t.timestamps
    end
    add_index :nevaeh_goal_steps,[:nevaeh_goal_id,:key],unique:true
  end
end
