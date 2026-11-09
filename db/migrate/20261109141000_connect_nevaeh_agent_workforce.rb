# frozen_string_literal: true
class ConnectNevaehAgentWorkforce < ActiveRecord::Migration[8.0]
  def change
    add_column :nevaeh_os_agents,:system_key,:string
    add_column :nevaeh_os_agents,:enabled,:boolean,null:false,default:true
    add_column :nevaeh_os_agents,:autonomy,:string,null:false,default:'manual'
    add_column :nevaeh_os_agents,:allowed_capabilities,:jsonb,null:false,default:[]
    add_index :nevaeh_os_agents,[:user_id,:system_key],unique:true
    create_table :nevaeh_agent_workers do |t|
      t.references :user,null:false,foreign_key:true
      t.references :nevaeh_os_agent,null:false,foreign_key:true
      t.string :name,null:false
      t.jsonb :command,null:false,default:{}
      t.boolean :enabled,null:false,default:true
      t.integer :interval_minutes
      t.datetime :next_run_at
      t.integer :lock_version,null:false,default:0
      t.timestamps
    end
    create_table :nevaeh_agent_runs do |t|
      t.references :nevaeh_agent_worker,null:false,foreign_key:true
      t.references :actor,null:false,foreign_key:{to_table: :users}
      t.references :nevaeh_os_action,foreign_key:true
      t.string :request_key,null:false
      t.string :status,null:false,default:'queued'
      t.jsonb :snapshot,null:false,default:{}
      t.text :error
      t.timestamps
    end
    add_index :nevaeh_agent_runs,[:nevaeh_agent_worker_id,:request_key],unique:true,name:'idx_nevaeh_agent_run_request'
  end
end
