class ScheduleNevaehJournalEditorial < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_blog_editorial_schedules do |t|
      t.bigint :site_id, null: false, index: { unique: true }
      t.bigint :actor_id, null: false
      t.bigint :last_goal_id
      t.string :delegation_id, null: false
      t.string :revision, null: false
      t.string :cadence, null: false
      t.string :article_status, null: false
      t.boolean :enabled, null: false, default: false
      t.boolean :social_draft, null: false, default: false
      t.json :topics, null: false
      t.json :sources, null: false
      t.datetime :next_run_at
      t.string :last_error, limit: 500
      t.timestamps
      t.index %i[enabled next_run_at]
    end
  end
end
