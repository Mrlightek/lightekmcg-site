class AddNevaehTaskDialogues < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_task_dialogues do |t|
      t.references :user,null:false,foreign_key:true
      t.string :request_key,null:false
      t.string :status,null:false,default:'collecting'
      t.text :request_text,null:false
      t.string :catalog_sha256,null:false
      t.jsonb :plan,null:false,default:[]
      t.jsonb :context,null:false,default:{}
      t.jsonb :interpretation,null:false,default:{}
      t.jsonb :response,null:false,default:{}
      t.references :nevaeh_os_action,foreign_key:true
      t.references :nevaeh_goal,foreign_key:true
      t.datetime :expires_at,null:false
      t.integer :lock_version,null:false,default:0
      t.timestamps
    end
    add_index :nevaeh_task_dialogues,[:user_id,:request_key],unique:true
    create_table :nevaeh_task_turns do |t|
      t.references :nevaeh_task_dialogue,null:false,foreign_key:true
      t.string :request_key,null:false
      t.string :input_sha256,null:false
      t.jsonb :input,null:false,default:{}
      t.jsonb :response,null:false,default:{}
      t.timestamps
    end
    add_index :nevaeh_task_turns,[:nevaeh_task_dialogue_id,:request_key],unique:true,name:'idx_nevaeh_task_turn_delivery'
    create_table :nevaeh_task_examples do |t|
      t.references :user,null:false,foreign_key:true
      t.references :nevaeh_task_dialogue,null:false,foreign_key:true
      t.text :phrase,null:false
      t.string :phrase_sha256,null:false
      t.string :task_key,null:false
      t.string :catalog_sha256,null:false
      t.string :status,null:false,default:'active'
      t.jsonb :evidence,null:false,default:[]
      t.timestamps
    end
    add_index :nevaeh_task_examples,[:user_id,:phrase_sha256,:catalog_sha256],unique:true,where:"status = 'active'",name:'idx_nevaeh_reviewed_task_phrase'
  end
end
