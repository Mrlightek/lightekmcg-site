class CreateNevaehs < ActiveRecord::Migration[8.0]
  def change
    create_table :nevaehs do |t|
      t.timestamps
    end
  end
end
