class CreateChannels < ActiveRecord::Migration[8.0]
  def change
    create_table :channels do |t|
      t.string :name
      t.string :logo
      t.references :show, null: false, foreign_key: true

      t.timestamps
    end
  end
end
