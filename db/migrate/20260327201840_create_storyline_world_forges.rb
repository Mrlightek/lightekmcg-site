class CreateStorylineWorldForges < ActiveRecord::Migration[8.0]
  def change
    create_table :storyline_world_forges do |t|
      t.timestamps
    end
  end
end
