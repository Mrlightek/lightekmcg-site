class IntegrateGatekeeperWithKbAndTickets < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:dymond_kb_articles, :metadata)
      add_column :dymond_kb_articles, :metadata, :jsonb, null: false, default: {}
      add_index :dymond_kb_articles, :metadata, using: :gin
    end

    drop_table :gatekeeper_escalations, if_exists: true
  end

  def down
    unless table_exists?(:gatekeeper_escalations)
      create_table :gatekeeper_escalations do |t|
        t.references :gatekeeper_operation, null: false, foreign_key: true
        t.string :category, null: false, default: "unknown_condition"
        t.string :status, null: false, default: "open"
        t.text :reason, null: false
        t.text :resolution
        t.boolean :capability_created, null: false, default: false
        t.datetime :resolved_at
        t.timestamps
      end
      add_index :gatekeeper_escalations, :status
      add_index :gatekeeper_escalations, :category
    end

    remove_index :dymond_kb_articles, :metadata if index_exists?(:dymond_kb_articles, :metadata)
    remove_column :dymond_kb_articles, :metadata if column_exists?(:dymond_kb_articles, :metadata)
  end
end
