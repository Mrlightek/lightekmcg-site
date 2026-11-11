# frozen_string_literal: true
class CreateNevaehWatchersAndEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_watchers do |t|
      t.references :user,null:false,foreign_key:true
      t.references :nevaeh_os_agent,null:false,foreign_key:true
      t.string :name,null:false
      t.string :kind,null:false
      t.jsonb :target,null:false,default:{}
      t.string :condition,null:false,default:'updated'
      t.string :response,null:false,default:'prepare'
      t.jsonb :command_template,null:false,default:{}
      t.string :status,null:false,default:'active'
      t.integer :interval_minutes,null:false,default:60
      t.jsonb :baseline,null:false,default:{}
      t.boolean :initialized,null:false,default:false
      t.datetime :next_poll_at
      t.datetime :last_polled_at
      t.string :lease_token
      t.datetime :lease_expires_at
      t.integer :poll_sequence,null:false,default:0
      t.integer :failures,null:false,default:0
      t.text :error
      t.integer :lock_version,null:false,default:0
      t.timestamps
    end
    create_table :nevaeh_watch_events do |t|
      t.references :nevaeh_watcher,null:false,foreign_key:true
      t.references :nevaeh_agent_run,foreign_key:true
      t.string :event_key,null:false
      t.string :entity,null:false
      t.string :change,null:false
      t.jsonb :before_value,null:false,default:{}
      t.jsonb :after_value,null:false,default:{}
      t.jsonb :plan,null:false,default:{}
      t.string :status,null:false,default:'detected'
      t.text :error
      t.timestamps
    end
    add_index :nevaeh_watch_events,[:nevaeh_watcher_id,:event_key],unique:true,name:'idx_nevaeh_watch_event_identity'
    add_index :nevaeh_watchers,[:status,:next_poll_at]
  end
end
