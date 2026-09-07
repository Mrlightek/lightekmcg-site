class CreateEpisodes < ActiveRecord::Migration[8.0]
  def change
    create_table :episodes do |t|
      t.string :title
      t.string :subtitle
      t.string :url
      t.text :description
      t.string :show_title
      t.text :show_description

      t.timestamps
    end
  end
end
