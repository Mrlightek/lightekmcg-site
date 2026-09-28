class ConnectArtifactsToStudioOperations < ActiveRecord::Migration[8.0]
  def change
    change_column_null :artifacts, :creation_job_id, true
    add_reference :artifacts, :studio_operation, null: true, foreign_key: true
  end
end
