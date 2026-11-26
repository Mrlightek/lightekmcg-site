class AddOwnerToStudioOperationRecords < ActiveRecord::Migration[8.0]
  def change
    add_reference :studio_operation_records, :owner, foreign_key: {to_table: :users, on_delete: :nullify}
  end
end
