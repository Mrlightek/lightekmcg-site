# frozen_string_literal: true
class CreateNevaehIslamicLibrary < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_islamic_sources do |t|
      t.references :creator, null: false, foreign_key: {to_table: :users}
      t.references :reviewer, foreign_key: {to_table: :users}
      t.datetime :reviewed_at
      t.string :name, null: false
      t.string :kind, null: false
      t.string :language, null: false
      t.string :edition, null: false
      t.string :tradition
      t.string :translator
      t.text :source_url, null: false
      t.text :attribution, null: false
      t.text :license, null: false
      t.text :permission_evidence
      t.boolean :training_permitted, null: false, default: false
      t.string :sha256, null: false
      t.string :status, null: false, default: 'draft'
      t.integer :passages_count, null: false, default: 0
      t.timestamps
    end
    add_index :nevaeh_islamic_sources, :sha256, unique: true
    create_table :nevaeh_islamic_passages do |t|
      t.references :nevaeh_islamic_source, null: false, foreign_key: true, index: {name: 'idx_islamic_passage_source'}
      t.string :reference, null: false
      t.text :body, null: false
      t.jsonb :assessments, null: false, default: []
      t.text :narrator
      t.string :sha256, null: false
      t.timestamps
    end
    add_index :nevaeh_islamic_passages, [:nevaeh_islamic_source_id, :reference], unique: true, name: 'idx_islamic_passage_reference'
  end
end
