class CreateStorylines < ActiveRecord::Migration[8.0]
  def change
    create_table :storylines do |t|
      t.timestamps
    end
  end
end
