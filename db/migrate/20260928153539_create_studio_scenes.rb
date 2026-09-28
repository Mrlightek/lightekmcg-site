class CreateStudioScenes < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_scenes do |t|
      t.references :studio_project, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
  end
end

