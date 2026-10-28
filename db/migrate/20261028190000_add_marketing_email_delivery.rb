class AddMarketingEmailDelivery < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_marketing_campaigns, :mail_account, foreign_key: {to_table: :lightek_mail_accounts}
    add_column :lightek_marketing_campaigns, :recipient_email, :string
    add_column :lightek_marketing_campaigns, :sent_at, :datetime
    add_column :lightek_marketing_campaigns, :mail_message_id, :bigint
    add_index :lightek_marketing_campaigns, :mail_message_id
  end
end
