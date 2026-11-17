class AddMemberBrandMailboxes < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :lightek_email_confirmed_at, :datetime
    add_column :lightek_mail_accounts, :brand_member, :boolean, null: false, default: false
  end
end
