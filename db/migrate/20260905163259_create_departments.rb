class CreateDepartments < ActiveRecord::Migration[8.0]
  def change
    create_table :departments do |t|
      t.string :title
      t.references :system_job, null: false, foreign_key: true

      t.timestamps
    end
  end
end
