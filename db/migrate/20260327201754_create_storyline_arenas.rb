class CreateStorylineArenas < ActiveRecord::Migration[8.0]
  def change
    create_table :storyline_arenas do |t|
      t.timestamps
    end
  end
end
