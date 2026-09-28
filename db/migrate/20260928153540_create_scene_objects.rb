class CreateSceneObjects < ActiveRecord::Migration[8.0]
  def change
    create_table :scene_objects do |t|
      t.references :studio_scene, null: false, foreign_key: true
      t.string :name, null: false
      t.string :object_type, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :definition, null: false, default: {}
      t.timestamps
    end
    add_index :scene_objects, %i[studio_scene_id position]
  end
end
