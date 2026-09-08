class CreateDatabaseRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :database_requests do |t|
      t.references :requestable, polymorphic: true, null: false
      t.jsonb :payload
      t.datetime :occurred_at

      t.timestamps
    end
  end
end
