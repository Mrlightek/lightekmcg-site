class CreateNevaehWorkspaces < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_workspaces do |t|
      t.references :user,null:false,foreign_key:true,index:{unique:true}
      t.json :panels,null:false,default:[]
      t.string :active_key
      t.integer :lock_version,null:false,default:0
      t.timestamps
    end
  end
end
