class AddEcosystemColumnsToUsers < ActiveRecord::Migration[8.0]
  def change
    # Add columns the ecosystem gems and app expect on users
    add_column :users, :first_name, :string,  null: false, default: ""
    add_column :users, :last_name,  :string,  null: false, default: ""
    add_column :users, :role,       :string,  null: false, default: "client"
    add_column :users, :phone,      :string
    add_column :users, :avatar_url, :string
    add_column :users, :timezone,   :string,  default: "Eastern Time (US & Canada)"
    add_column :users, :locale,     :string,  default: "en"

    add_index :users, :role
    #add_index :users, :email_address, unique: true  # ensure uniqueness at DB level
  end
end
