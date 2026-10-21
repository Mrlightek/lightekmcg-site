# frozen_string_literal: true
# Prepared only. Do not run against production without separate approval.
class CreateNevaehStudioIdempotencyRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaeh_studio_idempotency_records do |t|
      t.string :operation_key, null: false
      t.bigint :ticket_id, null: false
      t.string :work_order_sha256, null: false
      t.string :inputs_sha256, null: false
      t.bigint :work_item_id, null: false
      t.bigint :studio_project_id, null: false
      t.bigint :production_id, null: false
      t.bigint :studio_scene_id, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps null: false
    end
    add_index :nevaeh_studio_idempotency_records, :operation_key,
      unique: true, name: 'idx_nevaeh_studio_idempotency_operation_unique'
    add_index :nevaeh_studio_idempotency_records, :ticket_id,
      name: 'idx_nevaeh_studio_idempotency_ticket'
    add_index :nevaeh_studio_idempotency_records, :work_item_id,
      name: 'idx_nevaeh_studio_idempotency_work_item'
  end
end
