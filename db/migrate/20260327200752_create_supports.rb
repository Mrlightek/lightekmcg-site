class CreateSupports < ActiveRecord::Migration[8.0]
  def change
    create_table :supports do |t|
      t.timestamps
    end
  end
end
