class AddLightekEmailAddressToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :lightek_email_address, :string
    add_index :users, :lightek_email_address, unique: true
  end
end
