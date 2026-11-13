class AddFirstUsePasswordSetup < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :password_setup_required, :boolean, null: false, default: false
  end
end
