class AddGrowthAttributionToDemoRequests < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_agency_demo_requests, :growth_visit, foreign_key: { to_table: :lightek_growth_visits }
  end
end
