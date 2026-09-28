class CreateStudioProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_projects do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
  end
end
