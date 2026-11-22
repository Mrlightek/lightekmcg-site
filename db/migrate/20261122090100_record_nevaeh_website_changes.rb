class RecordNevaehWebsiteChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_growth_website_changes do |t|
      t.bigint :site_id, null: false, index: true
      t.bigint :action_id, null: false, index: { unique: true }
      t.bigint :actor_id, null: false
      t.string :operation, null: false
      t.json :previous_source
      t.json :result, null: false
      t.timestamps
    end
  end
end
