class AddProductionToStudioScenes < ActiveRecord::Migration[8.0]
  def change
    add_reference :studio_scenes, :production, null: true, foreign_key: true
  end
end
