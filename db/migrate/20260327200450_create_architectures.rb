class CreateArchitectures < ActiveRecord::Migration[8.0]
  def change
    create_table :architectures do |t|
      t.timestamps
    end
  end
end
