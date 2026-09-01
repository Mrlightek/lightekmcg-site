class AddUserToNevaeh < ActiveRecord::Migration[8.0]
  def change
    add_reference :nevaehs, :user, null: false, foreign_key: true
  end
end
