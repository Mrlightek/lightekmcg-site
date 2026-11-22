class CreateLightekExperiments < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_experiments do |t|
      t.bigint :site_id, null: false
      t.bigint :created_by_id, null: false
      t.string :name, null: false
      t.string :surface, null: false
      t.string :target, null: false, default: ''
      t.string :control, null: false
      t.string :challenger, null: false
      t.datetime :finished_at
      t.string :winner
      t.timestamps
    end
    add_index :lightek_experiments, [:site_id, :surface, :target], unique: true,
      where: 'finished_at IS NULL', name: 'idx_lightek_running_experiment'
    add_index :lightek_experiments, [:site_id, :id]

    create_table :lightek_experiment_assignments do |t|
      t.references :experiment, null: false, foreign_key: { to_table: :lightek_experiments }
      t.string :visitor_digest, null: false
      t.string :arm, null: false
      t.timestamps
    end
    add_index :lightek_experiment_assignments, [:experiment_id, :visitor_digest], unique: true,
      name: 'idx_lightek_experiment_visitor'
    add_index :lightek_experiment_assignments, :visitor_digest

    create_table :lightek_experiment_outcomes do |t|
      t.references :assignment, null: false, foreign_key: { to_table: :lightek_experiment_assignments }
      t.string :event, null: false
      t.bigint :record_id, null: false
      t.timestamps
    end
    add_index :lightek_experiment_outcomes, [:assignment_id, :event, :record_id], unique: true,
      name: 'idx_lightek_experiment_event'
  end
end
