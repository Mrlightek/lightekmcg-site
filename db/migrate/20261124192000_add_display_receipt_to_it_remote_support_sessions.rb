class AddDisplayReceiptToItRemoteSupportSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :it_remote_support_sessions, :display_reported_at, :datetime
  end
end
