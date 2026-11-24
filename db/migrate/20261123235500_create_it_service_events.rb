class CreateItServiceEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :it_service_events do |t|
      t.references :it_service_request, null: false, foreign_key: true, index: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :from_status, null: false
      t.string :to_status, null: false
      t.text :note, null: false
      t.timestamps
    end
  end
end
