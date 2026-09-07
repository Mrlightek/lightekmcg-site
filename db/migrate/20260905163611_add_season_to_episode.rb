class AddSeasonToEpisode < ActiveRecord::Migration[8.0]
  def change
    add_column :episodes, :season, :integer
  end
end
