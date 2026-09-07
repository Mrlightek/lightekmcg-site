class CreateShows < ActiveRecord::Migration[8.0]
  def change
    create_table :shows do |t|
      t.string :title
      t.string :network
      t.references :episode, null: false, foreign_key: true

      t.timestamps
    end
  end
end
