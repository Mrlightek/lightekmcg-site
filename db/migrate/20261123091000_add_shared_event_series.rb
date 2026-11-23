class AddSharedEventSeries < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_shared_events, :series_key, :string, limit: 36
    add_index :lightek_shared_events, %i[calendar_id series_key starts_at],
      where: 'series_key IS NOT NULL', name: 'index_shared_events_on_series_and_start'
  end
end
