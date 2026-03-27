class CreateStorylineWorldCommunities < ActiveRecord::Migration[8.0]
  def change
    create_table :storyline_world_communities do |t|
      t.timestamps
    end
  end
end
