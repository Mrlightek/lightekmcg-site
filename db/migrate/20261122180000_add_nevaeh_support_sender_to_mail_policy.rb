class AddNevaehSupportSenderToMailPolicy < ActiveRecord::Migration[8.0]
  def up
    add_column :lightek_mail_sending_policies, :nevaeh_support_sender, :jsonb,
      default: {}, null: false, if_not_exists: true
  end

  def down
    remove_column :lightek_mail_sending_policies, :nevaeh_support_sender, if_exists: true
  end
end
