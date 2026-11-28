# frozen_string_literal: true

class CreateLightekCommerceDisputeCases < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_dispute_cases do |t|
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}
      t.string :processor_reference, null: false
      t.string :status, null: false
      t.string :reason, null: false
      t.integer :amount_cents, null: false
      t.datetime :due_at
      t.datetime :alerted_at
      t.timestamps
      t.index :processor_reference, unique: true
    end
  end
end
