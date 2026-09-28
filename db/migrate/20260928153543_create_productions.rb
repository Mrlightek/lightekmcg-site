class CreateProductions < ActiveRecord::Migration[8.0]
  def change
    create_table :productions do |t|
      t.references :studio_project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "general"
      t.string :status, null: false, default: "development"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :productions, :status
    add_index :productions, [:studio_project_id, :name]
  end
end
