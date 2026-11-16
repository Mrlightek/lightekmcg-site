# frozen_string_literal: true
class AddStructuredWorkerResults < ActiveRecord::Migration[8.0]
  def change
    add_column :nevaeh_worker_reports, :structured_result, :jsonb, null:false, default:{}
  end
end
