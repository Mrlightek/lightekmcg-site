class CreateSystemJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :system_jobs do |t|
      t.string :name
      t.integer :priority
      t.references :job_item, null: false, foreign_key: true

      t.timestamps
    end
  end
end
