class CreatePressContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_press_contacts do |t|
      t.bigint :site_id, null: false
      t.string :email, null: false
      t.string :outlet, null: false
      t.string :contact_basis, null: false
      t.boolean :suppressed, null: false, default: false
      t.timestamps
    end
    add_index :lightek_press_contacts, [:site_id, :email], unique: true
  end
end
