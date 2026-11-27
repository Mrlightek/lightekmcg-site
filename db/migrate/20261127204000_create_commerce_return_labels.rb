class CreateCommerceReturnLabels < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_return_labels do |t|
      t.bigint :merchandise_return_id, null: false
      t.bigint :uploaded_by_id, null: false
      t.string :carrier, limit: 10
      t.string :tracking_number, limit: 35
      t.binary :pdf, null: false
      t.timestamps
      t.index :merchandise_return_id, unique: true, name: 'idx_commerce_return_label'
      t.check_constraint "(carrier IS NULL AND tracking_number IS NULL) OR " \
        "(carrier IS NOT NULL AND carrier IN ('ups', 'fedex') AND tracking_number IS NOT NULL)",
        name: 'commerce_return_label_tracking'
    end
    add_foreign_key :lightek_commerce_return_labels, :lightek_commerce_merchandise_returns, column: :merchandise_return_id
  end
end
